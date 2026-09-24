/**
 * Etichette e testi condivisi fra sito, gestionale e app, così che la stessa cosa si chiami allo
 * stesso modo ovunque.
 */
import type { Database } from './types/database';

type EventType = Database['public']['Enums']['event_type'];

/** Tipo dell'evento (B3): etichetta singolare, per badge e filtri. */
export const EVENT_TYPE_LABELS: Record<EventType, string> = {
  evento: 'Evento',
  laboratorio: 'Laboratorio',
  incontro: 'Incontro',
};

/** Tipo dell'evento al plurale, per i filtri ("Tutti", "Eventi", "Laboratori", "Incontri"). */
export const EVENT_TYPE_LABELS_PLURAL: Record<EventType, string> = {
  evento: 'Eventi',
  laboratorio: 'Laboratori',
  incontro: 'Incontri',
};

export type TrialFeedbackQuestion = {
  key: 'accoglienza' | 'livello' | 'continuare';
  question: string;
  options: { value: string; label: string }[];
};

/**
 * Questionario dopo la lezione di prova (F6). Le chiavi e i valori sono gli stessi che
 * `submit_trial_feedback` accetta: cambiarli qui senza una migrazione fa rifiutare le risposte.
 */
export const TRIAL_FEEDBACK_RATING_QUESTION = "Com'è andata la lezione di prova?";

export const TRIAL_FEEDBACK_QUESTIONS: TrialFeedbackQuestion[] = [
  {
    key: 'accoglienza',
    question: 'Ti sei sentitə a tuo agio?',
    options: [
      { value: 'si', label: 'Sì' },
      { value: 'abbastanza', label: 'Abbastanza' },
      { value: 'no', label: 'Non molto' },
    ],
  },
  {
    key: 'livello',
    question: 'Il livello della lezione era adatto a te?',
    options: [
      { value: 'giusto', label: 'Giusto per me' },
      { value: 'facile', label: 'Troppo facile' },
      { value: 'impegnativo', label: 'Troppo impegnativo' },
    ],
  },
  {
    key: 'continuare',
    question: 'Pensi di continuare?',
    options: [
      { value: 'si', label: 'Sì' },
      { value: 'forse', label: 'Forse' },
      { value: 'no', label: 'Per ora no' },
    ],
  },
];

export const TRIAL_FEEDBACK_COMMENT_QUESTION = 'Vuoi dirci altro?';
