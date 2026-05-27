import 'package:injectable/injectable.dart';

enum Env {
  DEVELOPMENT(_development),
  STAGING(_staging),
  PRODUCTION(_production),
  TEST(_test),
  DEMO(_demo);

  const Env(this.name);
  final String name;
}

const _development = 'development';
const _staging = 'staging';
const _production = 'production';
const _test = 'test';
const _demo = 'demo';

const development = Environment(_development);
const staging = Environment(_staging);
const production = Environment(_production);
const testEnvironment = Environment(_test);
const demo = Environment(_demo);
