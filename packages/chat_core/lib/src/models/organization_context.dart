class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.slug,
    this.policyFlags = const {},
    this.isDefault = false,
  });

  final int id;
  final int organizationId;
  final String name;
  final String slug;
  final Map<String, dynamic> policyFlags;
  final bool isDefault;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) {
    return WorkspaceSummary(
      id: json['id'] as int,
      organizationId: json['organization_id'] as int,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      policyFlags: (json['policy_flags'] as Map<String, dynamic>?) ?? const {},
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

class OrganizationSummary {
  const OrganizationSummary({
    required this.id,
    required this.name,
    required this.slug,
    this.brandColor = '',
    this.brandLogoUrl = '',
    this.currentRole = 'member',
    this.workspaces = const [],
  });

  final int id;
  final String name;
  final String slug;
  final String brandColor;
  final String brandLogoUrl;
  final String currentRole;
  final List<WorkspaceSummary> workspaces;

  factory OrganizationSummary.fromJson(Map<String, dynamic> json) {
    return OrganizationSummary(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      brandColor: json['brand_color'] as String? ?? '',
      brandLogoUrl: json['brand_logo_url'] as String? ?? '',
      currentRole: json['current_role'] as String? ?? 'member',
      workspaces: (json['workspaces'] as List<dynamic>? ?? const [])
          .map(
            (item) => WorkspaceSummary.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
