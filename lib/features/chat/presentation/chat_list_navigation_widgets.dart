part of 'chat_list_page.dart';

class _PremiumIconButton extends StatelessWidget {
  const _PremiumIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      style: IconButton.styleFrom(
        backgroundColor: context.appColors.surfaceMuted,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(
          color: context.appColors.border.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _PremiumBottomNavigation extends StatelessWidget {
  const _PremiumBottomNavigation({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_TabMeta> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(
              child: Semantics(
                selected: selectedIndex == index,
                button: true,
                label: tabs[index].label,
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: context.appDurations.fast,
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selectedIndex == index
                          ? colors.primarySoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        context.appRadii.pill,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          duration: context.appDurations.fast,
                          scale: selectedIndex == index ? 1.06 : 1,
                          child: HugeIcon(
                            icon: tabs[index].icon,
                            size: 20,
                            strokeWidth: selectedIndex == index ? 2.1 : 1.7,
                            color: selectedIndex == index
                                ? colors.primary
                                : colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tabs[index].label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: 10,
                                height: 1,
                                color: selectedIndex == index
                                    ? colors.primary
                                    : colors.textMuted,
                                fontWeight: selectedIndex == index
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
