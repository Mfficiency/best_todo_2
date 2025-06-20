class Config {
  static const bool isProduction = bool.fromEnvironment('dart.vm.product');
  static const bool isDev = !isProduction;
}
