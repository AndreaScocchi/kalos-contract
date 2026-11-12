-- Migration 20261112120000: blocchi «citazione» e «domanda per il Diario» nelle pratiche
--
-- Richiesta dell'utente del 12/11/2026: portare nella Pratica a casa le tre pratiche di scrittura
-- dei Cerchi Sociali sulla cura. Servono due blocchi nuovi:
--
--   * `quote`: un brano citato. `content` è il testo, `caption` la fonte (autore, titolo, editore,
--     anno). L'app lo mostra come citazione, con la fonte sotto.
--   * `journal_prompt`: una domanda di scrittura. `content` è la domanda, `caption` un suggerimento
--     facoltativo. L'app lascia lo spazio per rispondere dentro la pratica e salva domanda e risposta
--     come nota del Diario (`journal_entries`, con `practice_id`). Nessuna colonna nuova: la nota
--     è una nota come le altre, privata, e la prima del giorno conta 10 Punti Kalòs come sempre.
--
-- Solo valori nuovi dell'enum: le policy di `practice_blocks` e `journal_entries` restano quelle.
-- Un'app vecchia che incontra un tipo che non conosce non lo mostra.

ALTER TYPE "public"."practice_block_type" ADD VALUE IF NOT EXISTS 'quote';
ALTER TYPE "public"."practice_block_type" ADD VALUE IF NOT EXISTS 'journal_prompt';

COMMENT ON TABLE "public"."practice_blocks" IS
    'Blocchi di contenuto dentro uno step di pratica: testo, immagine, audio, video, citazione (content = brano, caption = fonte) e domanda per il Diario (content = domanda, caption = suggerimento).';
