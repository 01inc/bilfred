'use client';
import { useState, type FormEvent } from 'react';
import { Button } from '@base-ui/react/button';
import { Checkbox } from '@base-ui/react/checkbox';
import { CONSENT_TEXT, CONSENT_VERSION } from '@/lib/waitlist-schema';
import styles from './waitlist-form.module.css';

export function WaitlistForm() {
  const [consent, setConsent] = useState(false);
  const [state, setState] = useState<'idle' | 'loading' | 'success'>('idle');
  const [error, setError] = useState('');
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (state === 'loading') return;
    const data = new FormData(event.currentTarget);
    if (!consent) { setError('Gi samtykke for å melde deg på.'); return; }
    setState('loading'); setError('');
    try {
      const response = await fetch('/api/waitlist', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        signal: AbortSignal.timeout(10000),
        body: JSON.stringify({ email: data.get('email'), consent, consentVersion: CONSENT_VERSION, website: data.get('website') || '' }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Prøv igjen om et øyeblikk.');
      setState('success');
    } catch (issue) {
      setError(issue instanceof Error && issue.name !== 'TimeoutError' ? issue.message : 'Vi fikk ikke kontakt. Prøv igjen.');
      setState('idle');
    }
  }
  if (state === 'success') return <div className={styles.success} role="status"><span aria-hidden="true">✓</span><h2>Du står på listen</h2><p>Vi gir deg beskjed når Bilfred er klar til å prøves.</p></div>;
  return <form className={styles.form} onSubmit={submit} aria-label="Venteliste" aria-busy={state === 'loading'}>
    <label className={styles.emailLabel} htmlFor="email">Få tidlig tilgang</label>
    <div className={styles.row}>
      <input id="email" name="email" type="email" placeholder="E-postadressen din" autoComplete="email" maxLength={254} required aria-describedby={error ? 'form-error' : undefined} disabled={state === 'loading'} />
      <Button type="submit" disabled={state === 'loading'} className={styles.submit}>
        {state === 'loading' ? <span className={styles.spinner} aria-label="Lagrer" /> : <>Meld meg på <span aria-hidden="true">↗</span></>}
      </Button>
    </div>
    <div className={styles.trap} aria-hidden="true"><label htmlFor="website">Nettside</label><input id="website" name="website" tabIndex={-1} autoComplete="off" /></div>
    <label className={styles.consent}>
      <Checkbox.Root name="consent" checked={consent} onCheckedChange={setConsent} required disabled={state === 'loading'} className={styles.checkbox}>
        <Checkbox.Indicator>✓</Checkbox.Indicator>
      </Checkbox.Root>
      <span>{CONSENT_TEXT}</span>
    </label>
    {error && <p id="form-error" className={styles.error} role="alert">{error}</p>}
    <p className={styles.privacy}>Les om hvordan vi behandler opplysningene dine i <a href="/personvern">personvernerklæringen</a>.</p>
  </form>;
}
