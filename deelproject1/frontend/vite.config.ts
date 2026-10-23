/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Aspire sets API_HTTP(S); a plain `npm run dev` falls back to the API's http launch profile
const apiUrl = process.env.API_HTTPS || process.env.API_HTTP || 'http://localhost:5244'

const proxy = { '/api': { target: apiUrl, changeOrigin: true, secure: false } }

export default defineConfig({
  plugins: [react()],
  server: { proxy },
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts', './tests/msal.ts'],
    css: false,
    reporters: ['default', 'junit'],
    outputFile: { junit: './test-results/junit.xml' },
    coverage: {
      provider: 'v8',
      // lcov is read by SonarQube, text-summary is shown in the CI log
      reporter: ['text-summary', 'lcov', 'cobertura'],
      reportsDirectory: './coverage',
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['src/main.tsx', 'src/**/*.d.ts'],
      // Quality rule Q2 (docs/QUALITY_AND_SECURITY.md): minimum 80% coverage
      thresholds: { lines: 80, statements: 80, functions: 80, branches: 80 },
    },
  },
})
