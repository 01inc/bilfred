import type { Metadata } from 'next';
import styles from './privacy.module.css';
export const metadata: Metadata = { title: 'Personvern — Bilfred', alternates: { canonical: '/personvern' } };
export default function Privacy() { return <main className={styles.page}>
  <a className={styles.back} href="/">← Bilfred</a><h1>Personvern</h1><p>Sist oppdatert 8. november 2026.</p>
  <h2>Ventelisten</h2><p>Bilfred er et prosjekt fra <a href="https://01.inc">Zero One Labs</a>. Når du melder deg på, lagrer vi e-postadressen din, teksten du samtykket til, versjonen av teksten og tidspunktet for samtykket. Vi bruker dette bare til å gi deg informasjon om tidlig tilgang og lansering av Bilfred.</p>
  <h2>Ditt valg</h2><p>Påmelding er frivillig. Behandlingen bygger på samtykket ditt. Du kan når som helst trekke det tilbake eller be om innsyn, retting eller sletting ved å skrive til <a href="mailto:privacy@01.inc?subject=Bilfred%20venteliste">privacy@01.inc</a>. Vi lagrer påmeldingen i opptil ett år og sletter den tidligere hvis du ber om det.</p>
  <h2>Lagring og leverandører</h2><p>E-post og samtykke lagres i Bilfreds PostgreSQL-database hos Google Cloud i Frankfurt. Nettsiden leveres av Vercel. Disse leverandørene behandler tekniske forespørsler for å levere og sikre tjenesten. Sikkerhetskopier av databasen beholdes i sju dager.</p><p>For å begrense misbruk lagres kortvarige tellere med en daglig, beskyttet kode avledet fra IP-adressen. Vi lagrer ikke IP-adressen i ventelisten. Tellerne slettes etter ett døgn. Leverandørene kan behandle egne drifts- og sikkerhetslogger.</p>
  <h2>Ingen sporingsverktøy</h2><p>Denne siden bruker ikke analysepiksler, markedsføringsverktøy eller informasjonskapsler for sporing. Vi selger ikke e-postadressen din.</p>
  <h2>Kontakt</h2><p>Kontakt oss på <a href="mailto:privacy@01.inc">privacy@01.inc</a> om opplysningene dine. Du kan også klage til <a href="https://www.datatilsynet.no/">Datatilsynet</a>.</p>
</main>; }
