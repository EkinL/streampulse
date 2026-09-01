# Scalabilite et couts

Ce document chiffre ce que StreamPulse encaisse, ce que ca coute, et ou se
situe le mur. Toutes les valeurs sont **mesurees**, pas estimees : les
commandes de reproduction sont donnees a chaque fois.

## Environnement de mesure

| | |
|---|---|
| Machine | Apple M4, 10 coeurs (4 performance + 6 efficacite), 16 Go |
| Go | 1.26.1, `darwin/arm64` |
| Chunk audio | 4 KiB (`buf := make([]byte, 4096)` dans `Broadcast`) |
| Tampon par auditeur | 256 chunks (`clientBufferSize` dans `streaming/client.go`) |

Les mesures de reference de l'[ADR 003](ADR/003-streaming-sse.md) ont ete
prises sur un M1 Pro et sont environ 2,5x plus lentes. Les ordres de grandeur
et les conclusions sont identiques ; seules les valeurs absolues changent.

## 1. Cout du fan-out seul

```bash
cd backend && make bench
```

| Auditeurs | Temps / chunk 4 KiB | Cout / auditeur | Debit | Allocations |
|-----------|--------------------:|----------------:|------:|------------:|
| 10 | 5,3 us | 530 ns | 7,7 GB/s | 11 |
| 100 | 61,7 us | 617 ns | 6,6 GB/s | 101 |
| 1 000 | 494 us | 494 ns | 8,3 GB/s | 1 001 |
| 10 000 | 7,21 ms | 721 ns | 5,7 GB/s | 10 000 |

Connexion + deconnexion d'un auditeur : **885 ns**, 9 allocations.

Deux lectures :

- **Le cout par auditeur est plat** entre 10 et 10 000 (530 -> 721 ns). Le
  fan-out est lineaire, il n'y a pas de degradation super-lineaire. C'est ce
  que le sujet demande de prouver pour les goroutines et les channels.
- **Une allocation par auditeur et par chunk.** `Client.Send` copie le chunk
  pour chaque destinataire (`buf := make([]byte, len(data))`), soit 4 KiB
  alloues par auditeur et par chunk. C'est le poste dominant, et c'est un
  choix : sans la copie, un auditeur lent ferait muter le tampon des autres.

## 2. Cout de bout en bout

Le benchmark ci-dessus ne mesure que le Hub. Le cout reel inclut l'ecriture
HTTP, l'encodage base64 du SSE, le JWT, le RBAC et le rate-limit.

```bash
cd backend && make load-test
```

> 500 SSE listeners x 256 KiB = 125.0 MiB delivered end-to-end in 325.6 ms
> (**384 MiB/s**)

**Le pipeline complet debite 384 MiB/s de charge utile**, contre 8,3 GB/s pour
le Hub seul : le fan-out va environ **20x plus vite que le chemin qui
l'entoure**. Le facteur limitant est ailleurs — ecriture socket, encodage SSE,
middlewares.

> Les deux mesures ne sont pas dans la meme unite et ne doivent pas etre
> soustraites : le benchmark du Hub mesure du temps CPU sur une seule goroutine,
> le test de charge mesure du temps ecoule avec 500 clients concurrents sur
> 10 coeurs. Le rapport de debit reste neanmoins concluant sur l'ordre de
> grandeur.

Conclusion operationnelle : optimiser le Hub ne servirait a rien. Si un jour
il faut aller plus vite, c'est le chemin d'ecriture qu'il faut regarder.

### Surcout du SSE

`/streams/{id}/listen` encode chaque chunk en base64 et l'entoure du cadrage
SSE :

```
4096 octets -> 5464 octets base64 + "data: " + "\n\n" = 5472 octets
```

Soit **+33,6 % de bande passante**. L'[ADR 003](ADR/003-streaming-sse.md)
enregistre ce surcout comme une consequence negative assumee du choix de SSE.

`/streams/{id}/audio` diffuse les octets bruts, sans surcout : c'est la reponse
apportee a cette consequence, et c'est ce que l'app mobile consomme
(`live_stream_provider.dart`, qui appelle `ApiEndpoints.stream(id) + '/audio'`).
Le SSE reste servi pour les clients qui ne savent lire qu'un flux d'evenements.

## 3. Extrapolation : 100 flux simultanes

Hypotheses : 100 flux actifs, 50 auditeurs par flux (**5 000 auditeurs**),
audio MP3 a 128 kbit/s, soit 16 Ko/s par auditeur et 4 chunks de 4 KiB par
seconde et par flux.

### CPU

```
5 000 auditeurs x 4 chunks/s x 721 ns  =  14,4 ms de CPU par seconde
```

**1,4 % d'un coeur** pour le fan-out. Meme en prenant le cout de bout en bout
mesure au point 2, on reste tres loin de la saturation : le debit utile
demande est de 80 Mo/s, contre 384 Mio/s mesures, soit **20 % de la capacite
du pipeline**.

Le CPU n'est pas le facteur limitant, et de loin.

### Reseau

| Endpoint | Par auditeur | 5 000 auditeurs |
|----------|-------------:|----------------:|
| `/audio` (brut) | 16 Ko/s | 80 Mo/s = **640 Mbit/s** |
| `/listen` (SSE) | 21,4 Ko/s | 107 Mo/s = **856 Mbit/s** |

**Voila le mur.** Une carte 1 Gbit/s est saturee a 100 flux x 50 auditeurs en
SSE, et frolee en flux brut. Le serveur, lui, tourne a 20 % de sa capacite.

Plafond par interface reseau, en flux brut a 128 kbit/s :

| Interface | Auditeurs simultanes |
|-----------|---------------------:|
| 1 Gbit/s | ~7 800 |
| 10 Gbit/s | ~78 000 |

### Memoire

C'est le poste le plus risque, parce qu'il est invisible tant que tout va bien.

Chaque auditeur possede un channel tamponne de 256 chunks. Un auditeur qui
cesse de lire (reseau mobile qui decroche, application mise en veille) voit son
tampon se remplir :

```
256 chunks x 4 KiB = 1 MiB par auditeur bloque
```

| Auditeurs bloques simultanement | Memoire retenue |
|--------------------------------:|----------------:|
| 100 | 100 Mio |
| 1 000 | 1 Gio |
| 5 000 (tous) | **5 Gio** |

En regime nominal le tampon reste quasi vide et l'empreinte est negligeable.
Le pire cas, lui, depasse la RAM d'une machine modeste. La protection actuelle
est que `Client.Send` ne bloque jamais : quand le tampon est plein, le chunk
est **perdu pour cet auditeur seulement** (`select` avec `default`), ce que
`TestHubSlowListenerDoesNotBlockOthers` verifie. Un auditeur lent degrade donc
sa propre qualite, jamais celle des autres, et ne peut pas bloquer le
diffuseur.

### Goroutines

Une goroutine par connexion HTTP, plus une par diffuseur :

```
5 000 auditeurs + 100 diffuseurs = 5 100 goroutines
```

A ~8 Kio de pile initiale, environ **40 Mio**. Non significatif : Go tient des
centaines de milliers de goroutines sans difficulte.

## 4. Ou est le mur, en resume

| Ressource | A 100 flux x 50 auditeurs | Capacite | Utilisation |
|-----------|--------------------------:|---------:|------------:|
| CPU (fan-out) | 14,4 ms/s | 10 coeurs | **0,14 %** |
| CPU (pipeline complet) | 80 Mo/s | 384 Mio/s | **20 %** |
| Reseau (SSE) | 856 Mbit/s | 1 Gbit/s | **86 %** |
| Memoire (nominal) | negligeable | 16 Gio | ~0 % |
| Memoire (pire cas) | 5 Gio | 16 Gio | **31 %** |
| Goroutines | 5 100 | — | — |

**Le reseau sature en premier, a environ 4x l'utilisation CPU.** Le facteur
limitant de StreamPulse est la bande passante sortante, pas le code.

## 5. Consequences

### Ce qui ne sert a rien

Optimiser le Hub. Il debite 20x plus que le pipeline qui l'entoure, et son cout
par auditeur est deja plat jusqu'a 10 000.

### Ce qui aiderait vraiment

1. **Privilegier `/audio` sur `/listen`** partout ou le client sait consommer
   des octets bruts : **-33 % de bande passante** immediatement, sur le poste
   qui sature en premier. C'est le seul levier a un chiffre significatif.
2. **Borner le pire cas memoire.** `clientBufferSize` a 256 est genereux :
   4 chunks/s signifient qu'un auditeur a 64 secondes de retard avant de
   perdre quelque chose. Descendre a 64 (16 s de tolerance) diviserait le pire
   cas par quatre, a 1,25 Gio.
3. **Le transcodage** (bonus du sujet) attaquerait le vrai probleme : servir
   du 64 kbit/s aux clients en reseau contraint diviserait la bande passante
   par deux.

### Scalabilite horizontale

Le Hub est **en memoire du processus**. Deux instances derriere un load
balancer ne partagent pas leurs auditeurs : un diffuseur connecte a
l'instance A ne peut pas atteindre un auditeur connecte a l'instance B.

Passer horizontal exige donc soit des sessions collantes par flux (le
diffuseur et ses auditeurs sur la meme instance), soit un bus de messages
entre instances (Redis Pub/Sub, NATS). Vu le point 4, ce n'est pas urgent :
une seule instance sature deja une carte 1 Gbit/s.

## 6. Reproduire ces mesures

```bash
cd backend
make bench       # cout du fan-out a 10 / 100 / 1000 / 10000 auditeurs
make load-test   # 1000 auditeurs sur le Hub, puis 500 clients SSE reels
```

Les tests de charge tournent sous `-race` a chaque `go test ./...`, ce qui
garantit que les chiffres ci-dessus decrivent du code sans course de donnees.

---

## Summary (English)

All figures here are measured (`make bench`, `make load-test`), never
estimated. The in-memory fan-out Hub alone is essentially free: cost per
listener stays flat (530-721ns) from 10 to 10,000 listeners, at 8.3 GB/s
throughput. The full HTTP/SSE pipeline delivers 384 MiB/s end-to-end —
about 20x slower than the Hub alone, meaning the bottleneck is the
surrounding write path (socket I/O, SSE base64 framing, middleware), not
the Hub itself. Extrapolating to 100 concurrent streams x 50 listeners
each (5,000 listeners): CPU sits at 0.14% (fan-out) to 20% (full
pipeline), memory is negligible in the normal case but could reach 5 GiB
in the worst case (every listener's 256-chunk buffer full), and **the
network saturates first** — 856 Mbit/s of a 1 Gbit/s link over SSE, at
roughly 4x the CPU utilization. The actionable conclusion: optimizing the
Hub is pointless; favoring the raw-audio endpoint over SSE saves 33%
bandwidth immediately, and the Hub being purely in-process memory means
horizontal scaling needs sticky sessions or a cross-instance message bus —
not urgent, since one instance already saturates a 1 Gbit/s NIC.
