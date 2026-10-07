# Foto nello storage pubblico

Regole comuni a gestionale, sito, app e funzioni della newsletter, dal 07/10/2026.

## Perché

A ottobre 2026 Supabase ha avvisato che l'organizzazione, sul piano gratuito, aveva superato la
quota di traffico in uscita dalla cache: 5 GB di «cached egress». Il sito scaricava le foto a
grandezza piena, fino a 4 MB l'una e fino a 20 MB per una visita della home.

Le alternative scartate:

- **Il ridimensionamento di Supabase (`/storage/v1/render/image/…`)** non è incluso nel piano
  gratuito. L'app lo usava fino al 07/10/2026.
- **Netlify Image CDN.** A ogni server della CDN che non ha la foto in cache, Netlify la riscarica
  intera da Supabase: in una prova, 14 richieste a Netlify sono diventate 14 richieste a Supabase.
- **Piano Pro di Supabase.** L'utente non lo vuole.

Le foto quindi si comprimono **nel gestionale, nel browser di chi le carica**, e Supabase conserva
solo file già ottimizzati.

## Percorsi

| Percorso nel bucket | Cos'è |
|---|---|
| `<percorso>` | Originale, al massimo 2400×3600 px |
| `varianti/<percorso>/w480` | WebP larga 480 px |
| `varianti/<percorso>/w960` | WebP larga 960 px |
| `varianti/<percorso>/w1600` | WebP larga 1600 px |
| `varianti/<percorso>/w2400` | WebP larga 2400 px |
| `varianti/<percorso>/jpeg1200` | JPEG larga 1200 px, per email e anteprime dei link (Outlook per Windows non legge WebP) |

- **Le versioni non si ingrandiscono.** Una foto larga 1080 px ha `w1600` e `w2400` larghe 1080.
- **I nomi delle versioni non hanno estensione.** Il tipo sta nel `Content-Type` salvato con il file.
- **Bucket:** `activities`, `events`, `newsletter`, `operators`, `marketing`, `practices`. Le policy
  di scrittura dello staff valgono per tutto il bucket, quindi anche per `varianti/`.
- **Cache:** un anno (`max-age=31536000`), perché il gestionale non riusa mai un nome di file.

## Compressione (kalos-management, `src/lib/foto`)

La compressione usa i codec di Squoosh in WebAssembly (`@jsquash/*`), gli stessi algoritmi di
sharp, e gira in un worker.

- **Lettura.** Il browser legge la foto: applica l'orientamento della fotocamera e converte i
  colori in sRGB. Su iPhone e iPad Safari non legge oltre 16 megapixel: le foto più grandi
  arrivano un po' ridotte. Sui computer la lettura va fino a 50 megapixel e la riduzione la fa solo
  Lanczos.
- **Riduzione.** Lanczos3 in luce lineare.
- **Originale JPEG.** Si ricodifica con mozjpeg a qualità 88 (4:2:0, progressivo) solo se supera le
  misure o se risparmia almeno il 15%. Altrimenti resta il file com'è.
- **Originale PNG.** Oxipng senza perdita: i pixel restano identici.
- **Originale WebP.** Resta com'è, a meno che superi le misure: in quel caso qualità 90.
- **Originale in altri formati** (HEIC letto da Safari). Diventa JPEG, oppure PNG se ha parti
  trasparenti.
- **GIF.** Resta com'è e non ha versioni, perché può essere animata.
- **Versioni WebP.** Qualità 82, `use_sharp_yuv`, trasparenza conservata.
- **Versione `jpeg1200`.** Mozjpeg a qualità 85 in 4:4:4, per i testi delle locandine; le parti
  trasparenti diventano bianche.
- **Se il browser non riesce a comprimere,** si carica l'originale senza versioni, ma solo se pesa
  meno di 5 MB.

Le qualità sono state scelte per non vedere differenze al 100%. Il 07/10/2026 il risultato nel
browser era uguale a sharp con le stesse impostazioni: SSIM 0,962 contro 0,962.

## Chi legge le versioni

| Dove | File | Se la versione manca |
|---|---|---|
| Sito | `kalos-website/kalos-react/src/utils/images.ts`, `components/Foto.tsx` (`srcset` e `sizes`), `useSfondoFoto` per gli sfondi | Mostra l'originale |
| Sito, anteprime dei link | `scripts/prerender.mjs` (`fotoCondivisione`) | Usa l'originale (controlla con HEAD) |
| App | `kalos-app/src/domain/images.ts` (`sizedImageUrl`), `RemoteImage`, `Avatar` | Mostra l'originale |
| Newsletter | `supabase/functions/_shared/fotoEmail.ts` (`jpeg1200`) | Usa l'originale (controlla con HEAD) |
| Gestionale | `src/components/common/FotoArchivio.tsx`, `ActivityImage`, `PracticeImage` | Mostra l'originale |

## Foto caricate prima delle versioni

Gestionale → **Sistema → Foto** (solo admin) conta le foto senza versioni e le crea nel browser
con la stessa compressione. L'originale non si tocca. Il 07/10/2026 le 15 foto più pesanti erano
già state compresse a parte: originali salvati in `kalos-contract/backups/storage-originali-2026-10-07/`,
cartella esclusa da git.

## Da non fare

- Non usare `render/image` di Supabase né Netlify Image CDN per queste foto.
- Non caricare foto senza passare da `caricaFoto` (`src/lib/foto`).
- Non cambiare i percorsi delle versioni senza aggiornare tutti i lettori della tabella sopra.
