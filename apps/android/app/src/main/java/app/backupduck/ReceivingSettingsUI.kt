package app.backupduck

import android.view.View
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity

internal fun AppCompatActivity.showThermalSettings(changed:()->Unit={}):DuckSheet {
    val sheet=DuckSheet(this,getString(R.string.duck_thermal))
    sheet.body.addView(duckParagraph(getString(R.string.receiver_thermal_explanation)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
    val group=duckGroup(sheet.body)
    receiverSetting(group,getString(R.string.duck_thermal),getString(R.string.duck_thermal_off_note),duckSwitch(ReceiverThermalSettings.enabled(this)) {
        ReceiverThermalSettings.setEnabled(this,it);changed()
    })
    val choices=duckGroup(sheet.body)
    val selection=mutableMapOf<Int,View>()
    ReceiverThermalSettings.choices.forEach {value ->
        val selected=duckPill(getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background)
        selected.visibility=if(value==ReceiverThermalSettings.threshold(this)) View.VISIBLE else View.INVISIBLE
        selection[value]=selected
        receiverSetting(choices,if(value==ReceiverThermalSettings.DEFAULT_CELSIUS) getString(R.string.duck_default_choice,value) else "$value °C",control=selected) {
            ReceiverThermalSettings.setThreshold(this,value)
            selection.forEach {(key,view)->view.visibility=if(key==value) View.VISIBLE else View.INVISIBLE};changed()
        }
    }
    sheet.show();return sheet
}
/** A2/I4: a persistent preference belongs on a pushed page, not a sheet. */
internal fun BackupDuckActivity.conversionSettingsPage(changed:()->Unit={}):LookPage {
    val page=LookPage(this,getString(R.string.pref_conversion),"conversion")
    val group=lookGroup(page.body)
    lookSwitchRow(group,null,getString(R.string.duck_allow_conversion),getString(R.string.duck_conversion_note),MotionConversionSettings.enabled(this)) {
        MotionConversionSettings.setEnabled(this,it);changed()
    }
    page.body.addView(duckParagraph(getString(R.string.duck_conversion_off_note)),LinearLayout.LayoutParams(-1,-2).apply {
        topMargin=token(R.dimen.duck_space_small)
    })
    return page
}
internal fun BackupDuckActivity.showConversionSettings(changed:()->Unit={}):LookPage =
    conversionSettingsPage(changed).also {it.show()}
