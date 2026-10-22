import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

const apiUrl = process.env.API_HTTPS || process.env.API_HTTP

const proxy = apiUrl
  ? { '/api': { target: apiUrl, changeOrigin: true, secure: false } }
  : undefined

export default defineConfig({
  plugins: [react()],
  server: { proxy },
})
