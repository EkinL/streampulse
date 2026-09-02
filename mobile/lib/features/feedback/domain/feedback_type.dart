import 'package:flutter/material.dart';

/// Mirrors `domain.FeedbackType` on the backend (`bug`, `suggestion`,
/// `other`) - the string sent as `type` in `POST /feedback` must match one
/// of these exactly.
enum FeedbackType {
  bug('bug', 'Bug', Icons.bug_report_outlined),
  suggestion('suggestion', 'Suggestion', Icons.lightbulb_outline),
  other('other', 'Autre', Icons.chat_bubble_outline);

  final String apiValue;
  final String label;
  final IconData icon;

  const FeedbackType(this.apiValue, this.label, this.icon);
}
