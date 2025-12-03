import '@testing-library/jest-dom';

// Polyfill clipboard for tests
Object.assign(navigator, {
  clipboard: {
    writeText: async () => {},
    readText: async () => '',
  },
});

