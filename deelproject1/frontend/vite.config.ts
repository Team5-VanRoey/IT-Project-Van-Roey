/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

const apiUrl = process.env.API_HTTPS || process.env.API_HTTP

const proxy = apiUrl
  ? { '/api': { target: apiUrl, changeOrigin: true, secure: false } }
  : undefined

export default defineConfig({
  plugins: [react()],
  server: { proxy },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts', './src/test/msal.ts'],
    css: false,
    reporters: ['default', 'junit'],
    outputFile: { junit: './test-results/junit.xml' },
    coverage: {
      provider: 'v8',
      // lcov is read by SonarQube, text-summary is shown in the CI log
      reporter: ['text-summary', 'lcov', 'cobertura'],
      reportsDirectory: './coverage',
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['src/main.tsx', 'src/test/**', 'src/**/*.test.{ts,tsx}', 'src/**/*.d.ts'],
      // Quality rule Q2 (docs/QUALITY_AND_SECURITY.md): minimum 80% coverage
      thresholds: { lines: 80, statements: 80, functions: 80, branches: 80 },
    },
  },
})
