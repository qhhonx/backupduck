# Website hosting and update compatibility

The website is static HTML, CSS and JavaScript. GitHub Pages can serve the
primary site at `https://backupduck.app`; no Vercel functions are required by
new clients. Build-time release selection replaces the request-time API.

The legacy Vercel compatibility deployment serves the `site` directory directly
and retains its serverless update endpoints. Its explicit empty build command
and `.` output directory prevent the Pages build script from changing the
existing compatibility deployment behavior.

Run `node --test site/tests/*.test.mjs` and `node site/build.mjs build/site`.
The build reads published GitHub releases, selects a complete release and writes
`releases.json` plus the exact signed `appcast.xml`. Application binaries stay
on GitHub Releases. Missing or invalid release data fails the build instead of
advertising partial downloads. Preview output with any local static server.

## Domain and deployment

1. Enable GitHub Pages with GitHub Actions as its publishing source.
2. Configure `backupduck.app` as the repository Pages custom domain. For Actions,
   the repository setting is required; a generated CNAME file alone is insufficient.
3. Point the apex domain to GitHub Pages using ALIAS/ANAME to `qhhonx.github.io`,
   or A records `185.199.108.153`, `185.199.109.153`, `185.199.110.153`,
   `185.199.111.153`. Point `www` CNAME to `qhhonx.github.io` if using that alias.
4. Enable HTTPS after domain verification/certificate provisioning completes.
5. Trigger Publish website and verify the ordinary domain, canonical link,
   localized content, downloads, privacy page and update endpoints.

The workflow also rebuilds after successful Publish apps runs on main. Release
publication with the default Actions token does not start a second workflow via
`release: published`; `workflow_run` provides the required follow-up instead.

[GitHub Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
and [custom domains](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
are the configuration references.

## Existing installations

Keep `https://backupduck.vercel.app/api/releases` and `/appcast.xml` operational
for clients installed before migration. The old serverless handlers select the
same published release. New clients use the custom domain. Do not redirect a
signed feed to HTML or remove the old hostname during the release transition.
Removing Vercel entirely is a later compatibility decision, not a prerequisite
for migrating the primary website.

Also retain the PhotoBridge Mac feed at
`https://photobridge-app.vercel.app/appcast.xml` for 0.1.x release discovery.
The Android 0.1.x checker has stricter legacy repository and filename checks;
see [upgrade compatibility](upgrading.md) before promising discovery or
installation to those clients.

Before shipping clients that embed the new domain, verify its HTTPS availability,
compare appcast bytes and signatures with the published asset, and exercise both
new and legacy update URLs. Domain configuration and deployment are operational
steps; editing source files does not prove that the domain is live.
