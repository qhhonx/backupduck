package app.backupduck

import android.view.View
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity

internal fun AppCompatActivity.showThermalSettings(changed:()->Unit={}):DuckSheet {
    val sheet=DuckSheet(this,getString(R.string.duck_thermal))
    sheet.body.addView(duckParagraph(getString(R.string.duck_thermal_intro)),LinearLayout.LayoutParams(-1,-2).apply {bottomMargin=dp(20)})
    val group=duckGroup(sheet.body)
    duckSetting(group,getString(R.string.duck_thermal),getString(R.string.duck_thermal_off_note),duckSwitch(ReceiverThermalSettings.enabled(this)) {
        ReceiverThermalSettings.setEnabled(this,it);changed()
    })
    val choices=duckGroup(sheet.body)
    val selection=mutableMapOf<Int,View>()
    ReceiverThermalSettings.choices.forEach {value ->
        val selected=duckPill(getString(R.string.duck_selected),R.color.duck_action,R.color.duck_action_background)
        selected.visibility=if(value==ReceiverThermalSettings.threshold(this)) View.VISIBLE else View.INVISIBLE
        selection[value]=selected
        duckSetting(choices,if(value==ReceiverThermalSettings.DEFAULT_CELSIUS) getString(R.string.duck_default_choice,value) else "$value °C",control=selected) {
            ReceiverThermalSettings.setThreshold(this,value)
            selection.forEach {(key,view)->view.visibility=if(key==value) View.VISIBLE else View.INVISIBLE};changed()
        }
    }
    duckNotice(sheet.body,getString(R.string.duck_automatic_resume),getString(R.string.duck_thermal_resume));sheet.show();return sheet
}
internal fun AppCompatActivity.showConversionSettings(changed:()->Unit={}):DuckSheet {
    val sheet=DuckSheet(this,getString(R.string.duck_conversion))
    val group=duckGroup(sheet.body)
    duckSetting(group,getString(R.string.duck_allow_conversion),getString(R.string.duck_conversion_note),duckSwitch(MotionConversionSettings.enabled(this)) {
        MotionConversionSettings.setEnabled(this,it);changed()
    })
    duckNotice(sheet.body,getString(R.string.duck_conversion_original),getString(R.string.duck_conversion_off_note))
    duckNotice(sheet.body,getString(R.string.duck_conversion_cloud_note));sheet.show();return sheet
}
