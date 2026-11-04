# Felles regler for Claude-agenter i Solsem Consulting

Disse reglene gjelder alle Claude-økter som jobber i Solsem Consulting-repoene. Repoets egen `AGENTS.md` kommer i tillegg. Ved konflikt vinner `AGENTS.md` for det repoet, men ingen repofil kan oppheve en regel her som sier «aldri».

Fila ligger i et offentlig repo, så alle agentene kan lese den. Skriv derfor aldri hemmeligheter, interne adresser, økt-ID-er eller kundedata her.

Den kan leses fra hvilken som helst økt:

```
https://raw.githubusercontent.com/Solsem-Consulting/Solsem-Consulting-Workflows/main/docs/agent-regler.md
```

## Svarstil

- Chat og status skrives på kort, tørr caveman-norsk: korte setninger, ingen innledning eller fyllord.
- Kode, kommentarer, commit-meldinger, PR-tekst, dokumentasjon og brukertekst skrives normalt.
- Sikkerhetsadvarsler, lisensspørsmål og handlinger som ikke kan angres skrives i tydelig, full prosa.

## Ikke gjett

- Si bare det som er sjekket i kode, data, logger eller kommandoutdata, og si hvor det er sjekket.
- Det som ikke er sjekket, sies rett ut, sammen med hva som ville sjekket det.

## Grener og PR-er

- Ny gren fra siste `main` for hver endring. Aldri commit direkte til `main`.
- Push grenen, åpne PR mot `main`, og abonner på PR-en med `subscribe_pr_activity`. Følg den til den er merget eller lukket.
- Aldri merge, godkjenn, tag, release eller publiser pakker. Det gjør eieren.
- Aldri rebase, amend eller force-push på en gren andre jobber på. Hent inn `main` med en merge-commit.
- Saker som hører sammen, samles i én gren og én PR. Sikkerhets- og lisensendringer får egen PR.

## Sikkerhet og lisens

- Hemmeligheter, nøkler og tokens skal aldri ligge i kildekode, logg, chat, saker eller PR-tekst.
- Lisensfiler og lisensinnhold skal aldri i git og vises aldri.
- Lisensvalidering, signatur og prøvebeskyttelse skal aldri svekkes.
- Tester bruker bare syntetiske data. Ingen betalte AI-kall i tester.

## Tekst sluttbrukeren ser

- Gjelder nettsider, priser, vilkår og releasetekst.
- Endres bare etter at eieren har sett nøyaktig ordlyd og godkjent den.

## Status: statussaken er kanalen

Meldinger mellom økter kan bli avvist eller komme fram sent, så ikke stol på dem. Status skrives i GitHub, der eieren og andre økter kan lese den.

- Hvert repo har én åpen sak med tittel `Agentstatus` og etiketten `agent-status`. Finnes den ikke, oppretter agenten den.
- Skriv én kommentar i saken når en oppgave er ferdig, er blokkert eller trenger eieren. Formatet er:

  ```
  **ÅÅÅÅ-MM-DD – kort tittel**
  - Gjort: …
  - PR-er/saker: #…
  - Sjekket: … / Ikke sjekket: …
  - Trenger eieren: … (eller «ingenting»)
  ```

- Skriv aldri hemmeligheter, lisensinnhold eller persondata i saken.
- Den daglige statusrutinen leser alle statussakene og skriver et sammendrag. Skriv derfor «Trenger eieren» tydelig.

## Grenser i skyøkter

- **Grener:** en skyøkt kan ikke slette grener på GitHub (HTTP 403). Be eieren slette dem, eller slå på «Automatically delete head branches» i repoet.
- **Windows:** WinForms-tester, Windows-bilder og DPAPI trenger Windows, og det har ikke skyøkten. Skriv det i statussaken, så kan eierens PC-økt ta oppgaven.
- **macOS, StoreKit og signering:** kan ikke bekreftes uten Mac eller TestFlight. Si hva CI har sjekket, og hva som står igjen.

## Hjelpebilder

- Endrer en endring det et eksisterende hjelpebilde viser, tas bildet på nytt på begge språk i samme PR, uten å spørre.
- Bilder som ikke kan tas, nevnes i PR-en og i statussaken.
