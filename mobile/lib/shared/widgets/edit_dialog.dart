import 'package:flutter/material.dart';
import '../../app/theme.dart';

class EditField {
  final String label;
  final TextEditingController controller;
  final int maxLines;

  const EditField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });
}

class EditDialog extends StatelessWidget {
  final String title;
  final List<EditField> fields;
  final VoidCallback onSave;

  const EditDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SP.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: SP.text1,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: fields.map((field) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: field.controller,
                maxLines: field.maxLines,
                style: const TextStyle(color: SP.text1, fontSize: 14),
                decoration: InputDecoration(
                  labelText: field.label,
                  labelStyle: const TextStyle(color: SP.text3, fontSize: 12),
                  filled: true,
                  fillColor: SP.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: SP.text3)),
        ),
        FilledButton(
          onPressed: () {
            onSave();
            Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: SP.accent,
            foregroundColor: SP.btnText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
