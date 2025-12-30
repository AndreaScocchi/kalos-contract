import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts'],
  format: ['cjs', 'esm'],
  dts: true,
  sourcemap: true,
  target: 'es2019',
  clean: true,
  splitting: false,
  treeshake: true,
  external: ['@supabase/supabase-js'],
  outDir: 'dist',
});

