import { WaitlistForm } from '@/components/waitlist-form';
import styles from './page.module.css';
export default function Home() {
  return <div className={styles.page}>
    <a className={styles.skip} href="#venteliste">Gå til ventelisten</a>
    <header className={styles.header}><a href="/" className={styles.brand}>Bilfred</a></header>
    <main className={styles.main}>
      <div className={styles.intro}><span className={styles.dot} />Snart på iPhone</div>
      <h1>Bilvedlikehold<br /><span>På cruisekontroll</span></h1>
      <p className={styles.description}>EU-kontroll, service og vedlikehold.<br />Samlet i én app som følger bilen din.</p>
      <section id="venteliste" className={styles.waitlist} aria-label="Tidlig tilgang"><WaitlistForm /></section>
      <div className={styles.steps} aria-label="Slik vil Bilfred fungere">
        <div><span>01</span><h2>Legg til bilen</h2><p>Registreringsnummeret er starten.</p></div>
        <div><span>02</span><h2>Se hva som nærmer seg</h2><p>Frister og vedlikehold i én tidslinje.</p></div>
        <div><span>03</span><h2>Velg et verksted</h2><p>Sammenlign beliggenhet, omdømme og pris.</p></div>
      </div>
      <section className={styles.market} aria-labelledby="market-title">
        <h2 id="market-title">Personbiler på veien</h2>
        <div className={styles.figures}>
          <div><strong>3<span> mill.</span></strong><p>i Norge*</p></div>
          <div><strong>11<span> mill.</span></strong><p>i Skandinavia*</p></div>
          <div><strong>256<span> mill.</span></strong><p>i EU</p></div>
        </div>
        <details className={styles.sources}><summary>Kilder og avgrensning</summary>
          <p>* Avrundede anslag for 2025. Skandinavia omfatter Norge, Sverige og Danmark. EU-tallet gjelder 2024, fra ACEAs rapport for 2026.</p>
          <p><a href="https://www.ssb.no/transport-og-reiseliv/landtransport/statistikk/bilparken">SSB</a> · <a href="https://www.trafa.se/vagtrafik/fordon/">Trafikanalys</a> · <a href="https://www.dst.dk/da/Statistik/udgivelser/NytHtml?cid=53924">Danmarks Statistik</a> · <a href="https://www.acea.auto/publication/report-vehicles-on-european-roads-2026/">ACEA</a></p>
        </details>
      </section>
    </main>
    <footer className={styles.footer}><span>Bilfred · Under utvikling</span><a href="/personvern">Personvern</a><span>Et prosjekt fra <a href="https://01.inc">Zero One Labs</a></span></footer>
  </div>;
}
