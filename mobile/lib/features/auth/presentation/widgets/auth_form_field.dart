import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

class AuthFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final void Function(String)? onFieldSubmitted;

  const AuthFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        validator: validator,
        onFieldSubmitted: onFieldSubmitted,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: SP.text1,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: SP.text3,
          ),
          prefixIcon: prefixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: IconTheme(
                    data: const IconThemeData(color: SP.text3, size: 20),
                    child: prefixIcon!,
                  ),
                )
              : null,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 0,
          ),
          suffixIcon: suffixIcon != null
              ? IconTheme(
                  data: const IconThemeData(color: SP.text3, size: 20),
                  child: suffixIcon!,
                )
              : null,
          filled: true,
          fillColor: SP.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SP.accent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: SP.error),
          ),
          contentPadding: const EdgeInsets.only(
            left: 48,
            right: 16,
            top: 18,
            bottom: 18,
          ),
        ),
      ),
    );
  }
}
