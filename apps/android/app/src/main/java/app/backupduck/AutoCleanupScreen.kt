package app.backupduck

import android.os.Bundle
import android.view.View
import android.widget.LinearLayout
import com.google.android.material.R as M

/** Ordinary cleanup controls over the shared journey and service. */
internal class AutoCleanupScreen(private val activity: MainActivity, restored: Bundle = Bundle()) {
    val page = LookPage(activity, activity.getString(R.string.storage_cleanup), "auto-cleanup")
    private val state = activity.lookText("", M.style.TextAppearance_Material3_TitleLarge)
    private val account = activity.lookText("", M.style.TextAppearance_Material3_BodyMedium, secondary = true)
    private val result = activity.lookText("", M.style.TextAppearance_Material3_BodyLarge)
    private val controls = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val journey: CleanupJourney
    init { with(activity) {
        page.state.putAll(restored)
        val card = lookCard(page.body)
        card.addView(state)
        card.addView(account, LinearLayout.LayoutParams(-1, -2).apply { topMargin = token(R.dimen.duck_space_small) })
        val last = lookContentSection(page.body, getString(R.string.auto_cleanup_last_result))
        lookCard(last).addView(result)
        page.body.addView(controls, LinearLayout.LayoutParams(-1,-2).apply { topMargin = token(R.dimen.duck_space_medium) })
        val explanation = lookContentSection(page.body, getString(R.string.auto_cleanup_how_title))
        lookCard(explanation).addView(lookText(getString(R.string.auto_cleanup_how), M.style.TextAppearance_Material3_BodyMedium, secondary = true))
        journey = CleanupJourney(this, page, ::render)
        page.resumed = { journey.resumed(); render() }
        page.setOnDismissListener { journey.close() }
        render()
    } }
    private fun render() = with(activity) {
        val facts = PhotosCleanup(this)
        state.text = getString(if (facts.enabled) R.string.pref_storage_cleanup_on else R.string.pref_storage_cleanup_off)
        state.append("\n" + journey.text())
        account.setSupporting(if (journey.running) getString(R.string.auto_cleanup_stop_note)
            else if (facts.account.isNotEmpty() && journey.status !in setOf(CleanupStatus.ACCOUNT, CleanupStatus.BINDING)) getString(R.string.auto_cleanup_account_confirmed) else null)
        result.text = journey.lastResult()
        // This bounded action group is rebuilt only when its state changes, preserving pressed/focus state.
        val key = "${journey.status}/${journey.pending}/${facts.enabled}/${page.state.getBoolean("cleanup-reviewed-return")}"
        if (controls.tag == key) return@with
        controls.tag = key; controls.removeAllViews()
        fun button(label: Int, style: LookButton = LookButton.TONAL, action: () -> Unit) {
            controls.addView(lookButton(getString(label), style, action = action), LinearLayout.LayoutParams(-1,-2).apply {
                topMargin = token(R.dimen.duck_space_x_small)
            })
        }
        if (journey.running) button(R.string.auto_cleanup_stop, action = journey::stop)
        else if (journey.status == CleanupStatus.REVIEW) {
            button(R.string.auto_cleanup_open_photos, LookButton.FILLED, journey::openPhotos)
            if (page.state.getBoolean("cleanup-reviewed-return"))
                button(R.string.auto_cleanup_reviewed, LookButton.TONAL, journey::reviewed)
            button(R.string.auto_cleanup_check_result, LookButton.TEXT, journey::run)
        } else {
            button(R.string.auto_cleanup_run, LookButton.FILLED, journey::run)
            if (journey.status == CleanupStatus.ACCESS) button(R.string.auto_cleanup_turn_on, action = journey::enable)
            else if (journey.status == CleanupStatus.UNAVAILABLE) button(R.string.auto_cleanup_open_photos, action = journey::openPhotos)
            button(R.string.auto_cleanup_confirm_again) { journey.confirm() }
        }
    }
}
