import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

enum NavTab { envoyer, recevoir, historique, parametres }

/// Bottom navigation bar matching the mockups (4 tabs with active pill indicator)
class PeerBottomNavBar extends StatelessWidget {
  const PeerBottomNavBar({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
  });

  final NavTab currentTab;
  final ValueChanged<NavTab> onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(
          top: BorderSide(
            color: AppTheme.ink.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _NavItem(
              icon: Icons.send_rounded,
              label: 'Envoyer',
              isSelected: currentTab == NavTab.envoyer,
              onTap: () => onTabSelected(NavTab.envoyer),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.download_rounded,
              label: 'Recevoir',
              isSelected: currentTab == NavTab.recevoir,
              onTap: () => onTabSelected(NavTab.recevoir),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.history_rounded,
              label: 'Historique',
              isSelected: currentTab == NavTab.historique,
              onTap: () => onTabSelected(NavTab.historique),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.settings_outlined,
              label: 'Paramètres',
              isSelected: currentTab == NavTab.parametres,
              onTap: () => onTabSelected(NavTab.parametres),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = AppTheme.indigo;
    final inactiveColor = AppTheme.ink.withValues(alpha: 0.35);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 3),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.indigo,
                ),
              ),
            ] else
              const SizedBox(height: 7),
          ],
        ),
      ),
    );
  }
}
