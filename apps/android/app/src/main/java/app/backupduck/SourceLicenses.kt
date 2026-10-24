package app.backupduck

import com.google.android.material.R as M

/** Native offline inventory generated from the resolved Android release dependencies. */
internal fun MainActivity.createSourceLicensesPage(): LookPage {
    val page = LookPage(this, getString(R.string.about_source_licenses), "source-licenses")
    val project = lookGroup(page.body)
    lookRow(project, R.drawable.ic_computer, getString(R.string.source_project)) {
        openSupportLink("https://github.com/qhhonx/backupduck")
    }
    lookRow(project, R.drawable.ic_document, "PolyForm Noncommercial 1.0.0", getString(R.string.source_project_license)) {
        createLicenseTextPage("project-license").show()
    }
    lookRow(project, R.drawable.ic_document, getString(R.string.source_third_party)) { createLicenseTextPage("third-party-notices").show() }
    return page
}

internal fun MainActivity.createLicenseTextPage(route: String): LookPage {
    val path = when (route) {
        "project-license" -> "project-license.txt"
        else -> "third-party-notices.txt"
    }
    val title = if (route == "project-license") "PolyForm Noncommercial 1.0.0"
        else getString(R.string.source_third_party)
    return LookPage(this, title, route).apply {
        body.addView(lookText(assets.open(path).bufferedReader().use { it.readText() },
            M.style.TextAppearance_Material3_BodySmall).apply { setTextIsSelectable(true) })
    }
}
