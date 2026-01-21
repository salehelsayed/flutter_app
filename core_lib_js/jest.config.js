module.exports = {
  preset: 'ts-jest/presets/default-esm',
  testEnvironment: 'node',
  testMatch: ['**/__test__/**/*.test.ts'],
  moduleFileExtensions: ['ts', 'js', 'mjs'],
  extensionsToTreatAsEsm: ['.ts'],
  transform: {
    '^.+\\.ts$': ['ts-jest', {
      useESM: true,
      tsconfig: '<rootDir>/../tsconfig.json',
    }],
  },
  transformIgnorePatterns: [
    'node_modules/(?!(@libp2p|@noble|multiformats|uint8arrays|uint8arraylist|protons-runtime)/)',
  ],
  moduleNameMapper: {
    '^(\\.{1,2}/.*)\\.js$': '$1',
  },
};
