// Run unchanged Web consumers against responses captured from the real backend.
import { fileURLToPath } from 'node:url'

const repo = fileURLToPath(new URL('../../', import.meta.url))
const dependency = (path: string) => fileURLToPath(new URL(`../../web/node_modules/${path}`, import.meta.url))
export default {
  root: fileURLToPath(new URL('../../web/', import.meta.url)),
  resolve: {
    dedupe: ['react', 'react-dom', '@tanstack/react-query'],
    alias: [
      { find: /^react$/, replacement: dependency('react/index.js') },
      { find: /^@tanstack\/react-query$/, replacement: dependency('@tanstack/react-query/build/modern/index.js') },
      { find: /^@testing-library\/react$/, replacement: dependency('@testing-library/react/dist/index.js') },
      { find: /^vitest$/, replacement: dependency('vitest/dist/index.js') },
      { find: /^msw$/, replacement: dependency('msw/lib/core/index.mjs') },
    ],
  },
  test: {
    dir: repo,
    include: ['backend/tests/agent_client_compat.test.ts'],
    environment: 'jsdom',
    setupFiles: [fileURLToPath(new URL('../../web/src/test/setup.ts', import.meta.url))],
  },
}
