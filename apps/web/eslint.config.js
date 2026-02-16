import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'

export default [
  { ignores: ['dist', 'src/api/**'] }, // Exclude generated code
  // typescript-eslint.configs.recommended is an array and must be spread at top level
  ...tseslint.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    ...js.configs.recommended,        // Spread just rules here
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: 'module',
      globals: globals.browser,
      parserOptions: {
        lib: ['ES2020', 'DOM'],       // For Web API types recognition
      },
    },
  },
  // React plugin configs as separate config objects
  reactHooks.configs.flat.recommended,
  reactRefresh.configs.vite,
]
