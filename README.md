# Solsem Consulting workflows

Felles GitHub Actions-kontrakter for CVSmia og Karemo.

## Release-kjede

1. Produktrepoets `.github/workflows/publish.yml` eier manuell/tag-trigger, konkrete paths og token-permissions.
2. `sc-core.yml` validerer repository/solution-kontrakten.
3. `SC-Build.yml` restorer og bygger løsningen med felles .NET-oppsett. Med input `test_projects` (JSON-liste med `.csproj`-stier) kjører den også produktets testprosjekter i samme jobb, rett etter bygget. Da betales checkout, .NET-oppsett og restore én gang, og testene bygger ikke om det som allerede er bygget.
4. `SC-Quality.yml` kjører testprosjektene i en egen jobb med egen checkout og eget bygg. Den beholdes for eksisterende referanser, men nye og oppdaterte produktrepo bør bruke `test_projects` i `SC-Build.yml` og droppe quality-jobben. Det sparer Windows-minutter per release.
5. Produktets lokale kandidat-workflow bygger og pakker release-filene én gang og laster dem opp som artefakten `release-candidate`.
6. `SC-Approval.yml` oppretter godkjenningssak før produksjonspublisering og viser SHA-256 for hver kandidatfil.
7. Produktets `publish.yml` kaller produktets lokale reusable deployment-workflow direkte med det godkjente manifestet.
8. Den lokale deployment-workflowen laster ned den godkjente kandidaten uten å bygge på nytt, verifiserer den og eier produktspesifikk signering, FTP-publisering og nettside-handoff.
9. `sc-post.yml` skriver felles sluttrapport og oppretter GitHub Release for tag-kjøringer.

Produktspesifikke deploy-kontrakter:

- `Solsem-Consulting/cvsmia`: `publish.yml` -> `./.github/workflows/release-publish-ftp.yml`
- `Solsem-Consulting/KaremoSuite`: `publish.yml` -> `./.github/workflows/publish-ftp.yml`

Det finnes med hensikt ingen felles deployment-router. Dermed trenger ikke Karemo å laste eller validere CVSmias deployment-workflow, og CVSmia trenger ikke å laste eller validere Karemo sin. Produktets deployment-workflow skal bare eksponere `workflow_call`; alle eksterne release-triggere eies av produktets `publish.yml`.

Begge private produktrepo må ha Actions access satt til organisasjonen slik at de felles build-, quality-, approval- og post-workflowene kan lastes. Secrets må sendes eksplisitt eller med `secrets: inherit` i hvert hopp. `SC-Build.yml` og `SC-Quality.yml` deklarerer de valgfrie secretene `NUGET_AUTH_TOKEN` og `GH_PACKAGES_READ_TOKEN`; uten dem brukes `github.token` mot pakkefeeden. `GITHUB_TOKEN`-permissions kan bare beholdes eller reduseres gjennom kjeden, derfor deklareres nødvendige write-permissions i produktets inngangsworkflow.

Alle jobber har `timeout-minutes`. `SC-Build.yml` og `SC-Quality.yml` har 60 minutter som standard, og `SC-Approval.yml` venter maksimalt 60 minutter på godkjenning, siden runneren holdes og belastes mens den venter. Alle tre kan overstyres med input `timeout_minutes`. `sc-core.yml` og `sc-post.yml` har faste 10 minutter.

`SC-Approval.yml` konfigureres med disse valgfrie inputene:

| Input | Standard | Beskrivelse |
|---|---|---|
| `approvers` | `HarrySolsem` | Kommaseparerte GitHub-brukere eller organisasjonsteam som kan godkjenne |
| `minimum_approvals` | `1` | Antall godkjenninger som kreves |
| `version_file` | tom | Tekstfil med versjonsnummer, brukes når versjon ikke er oppgitt |
| `release_tag` / `release_version` | tom | Overstyrer tag og versjon fra utløseren |
| `timeout_minutes` | `60` | Maksimal ventetid på godkjenning |
| `candidate_artifact` | tom | Artefakt med release-kandidaten; filene hashes og vises i godkjenningssaken |

`SC-Approval.yml` returnerer `approved_sha` (commiten godkjenningen gjelder), `candidate_manifest` (godkjent manifest i `sha256sum`-format) og `candidate_digest` (SHA-256 av manifestteksten). De to siste er tomme uten `candidate_artifact`.

Versjonen hentes i denne rekkefølgen: `release_version`, `workflow_dispatch`-input `version`, `version_file`, `Version` i `Directory.Build.props` på rotnivå. CVSmia har versjonen i `src/cvsmia/VERSION` og må derfor sende `version_file: src/cvsmia/VERSION`.

## Én godkjent kandidat per release

Hver release-kjøring bygger, tester og pakker én kandidat før godkjenning. Deploy etter godkjenning laster ned den samme artefakten og bygger aldri på nytt.

- Kandidaten lastes opp som artefakten `release-candidate` med `retention-days: 1`. Navnet er fast per kjøring, og artefakten skal bare inneholde filer som skal signeres eller publiseres.
- Signert payload lastes opp som `signed-release` med `retention-days: 1`. Artefakter fra en kjøring gjenbrukes aldri i en annen kjøring; en utløpt kandidat krever en ny release-kjøring med ny godkjenning.
- `.github/actions/candidate-manifest` lager manifestet: én linje `<sha256>  <relativ/sti>` per fil, sortert ordinalt på sti, med LF-linjeskift. `candidate_digest` er SHA-256 av denne teksten.
- Deploy kaller `candidate-manifest` med `expected-manifest` og `expected-digest` rett etter nedlasting. Actionen feiler hvis en fil mangler, er endret eller er lagt til.
- Signering skjer etter godkjenning. Signeringsjobben verifiserer kandidaten mot det godkjente manifestet før signering, lager et nytt manifest for de signerte filene og logger det. Publiseringsjobben verifiserer den signerte payloaden mot dette manifestet rett før opplasting. Filer som ikke endres av signering har dermed samme hash ved godkjenning og opplasting.

## Workflow-avhengigheter

Alle eksterne Actions og reusable workflows skal bruke full commit-SHA med lesbar versjon i kommentar. `workflow-pin-policy.yml` avviser mutable referanser og manglende versjonskommentar i pull requests. Dependabot kontrollerer GitHub Actions og validator-avhengighetene ukentlig. Review-forespørsler styres av `.github/CODEOWNERS`, siden Dependabot ikke lenger støtter `reviewers` i `dependabot.yml`.

Produktrepoene peker på én eksplisitt, gjennomgått commit i dette repoet. Promotering av en ny shared-workflow-versjon gjøres ved å oppdatere alle shared-workflow-referansene i hvert produktrepo til samme nye SHA i en reviewet pull request.

`workflow-validation.yml` kjører Actionlint med ShellCheck, validerer syntaksen i embedded PowerShell og Bash, og kontrollerer caller-inputs og secrets mot `workflow_call`-kontraktene. Referanser til dette repoets workflows som ikke er pinnet til full commit-SHA avvises. Steg med shells uten syntakssjekk (for eksempel `python` og `cmd`) hoppes over. Representative Karemo- og CVSmia-fixtures samt negative regresjons-fixtures ligger sammen med validator-actionen.
