import { z } from 'zod';
export const CONSENT_VERSION = '2026-11-08';
export const CONSENT_TEXT = 'Jeg vil få e-post om tidlig tilgang og lansering av Bilfred. Jeg kan trekke samtykket når som helst.';
export const waitlistSchema = z.object({
  email: z.string().trim().max(254).email(),
  consent: z.literal(true),
  consentVersion: z.literal(CONSENT_VERSION),
  website: z.string().max(200).default(''),
}).strict();
