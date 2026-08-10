import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:provider/provider.dart';
import '../../core/fund_provider.dart';

class MobileHeader extends StatelessWidget {
  final String title;
  final Widget? searchBox;
  final Widget? moreBtn;
  final Widget? extraBtn;

  const MobileHeader({
    super.key,
    required this.title,
    this.searchBox,
    this.moreBtn,
    this.extraBtn,
  });

  @override
  Widget build(BuildContext context) {
    final fundProvider = Provider.of<FundProvider>(context, listen: false);
    final theme = FluentTheme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.resources.subtleFillColorSecondary,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        top: false,
        child: SizedBox(
          height: 40.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.menu, size: 20),
                  onPressed: () => fundProvider.openDrawer(),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (searchBox != null) ...[
                  searchBox!,
                  const SizedBox(width: 8),
                ],
                if (moreBtn != null) ...[
                  moreBtn!,
                ],
                if (extraBtn != null) ...[
                  const SizedBox(width: 8),
                  extraBtn!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
