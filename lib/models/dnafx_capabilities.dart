class DnafxCapabilities {
  const DnafxCapabilities({
    required this.ampModels,
    required this.effectModels,
    required this.parameterNames,
  });

  final Set<String> ampModels;
  final Set<String> effectModels;
  final Set<String> parameterNames;
}
