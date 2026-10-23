package app.backupduck

import android.app.Instrumentation
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject

/** Mutable core replies drive the current Photos grid, filters and Home mosaic. */
internal fun Instrumentation.checkHistoryLive(args: Bundle): String {
    check(targetContext.packageName.endsWith(".validation") && android.os.Build.MODEL.contains("sdk_gphone"))
    val enabled = ReceiverPreferences.enabled(targetContext)
    val preview = ReceiverEnvironment.previewImage
    ReceiverPreferences.setEnabled(targetContext, false)
    targetContext.getSharedPreferences("appearance", 0).edit().putInt("mode", if (args.getString("dark") == "true") 2 else 1).commit()
    val activity = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
    fun <T> main(action: () -> T): T { var result: Result<T>? = null; runOnMainSync { result = runCatching(action) }; return result!!.getOrThrow() }
    fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    fun settle() { waitForIdleSync(); Thread.sleep(250); waitForIdleSync() }
    var rows = (1..240).map { i -> JSONObject().put("cursor", i).put("id", "generated-$i").put("filename", "Generated_$i.jpg")
        .put("kind", "photo").put("total_bytes", 100).put("confirmed_bytes", if (i == 240) 0 else 100)
        .put("receipt", if (i == 240) "receiving" else "received").put("processing", if (i > 238) "pending" else "complete")
        .put("processing_error", JSONObject.NULL).put("originals_released", false) }
    val queries = mutableListOf<JSONObject>()
    val model = HistoryModel { query ->
        queries += JSONObject(query.toString())
        val matching = rows.filter { query.getString("state") != "active" || it.getString("processing") == "pending" }.sortedByDescending { it.getLong("cursor") }
        val offset = query.optString("cursor").toIntOrNull() ?: 0
        val page = matching.drop(offset).take(100)
        JSONObject().put("items", JSONArray(page)).put("total", matching.size)
            .put("next_cursor", if (offset + page.size < matching.size) (offset + page.size).toString() else JSONObject.NULL)
            .put("counts", JSONObject().put("total", rows.size).put("published", rows.count { it.getString("processing") == "complete" }).put("failed", 0))
    }
    try {
        ReceiverEnvironment.previewImage = { _, w, h -> Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888) }
        runBlocking { model.select("synthetic-response") }
        val page = main { ReceivedPhotosPage(activity, ReceivedPhotosPage.Actions({}, {}, { it(true) }, { _, done -> done(true) }, {})).also {
            activity.setContentView(it.view); it.render(model.state.value)
        } }
        settle()
        val list = page.view
        val adapter = list.adapter as ListAdapter<*, *>
        val photos = list.adapter as PhotoTransitionItems
        check(main { photos.photoItems().size == 100 })
        val first = main { photos.positionOfPhoto("generated-240") }
        val holder = main { checkNotNull(list.findViewHolderForAdapterPosition(first)) }
        val image = main { views(holder.itemView).filterIsInstance<ImageView>().first { it.transitionName == photoTransitionName("generated-240") } }
        val drawable = main { image.drawable }
        for (confirmed in listOf(25L, 50L, 75L)) {
            main { page.progress(mapOf("generated-240" to ReceiverByteProgress(confirmed, 100, false))) }
            check(main { photos.photoItems().first().confirmedBytes == confirmed })
            check(main { image.drawable === drawable }) { "Byte updates restarted photo loading" }
        }
        main { adapter.notifyItemChanged(first) }; settle()
        check(main { photos.photoItems().first().confirmedBytes == 75L }) { "Old metadata rewound live byte progress" }
        main { page.progress(mapOf("generated-240" to ReceiverByteProgress(100, 100, true))) }
        check(main { photos.photoItems().first().mark == PhotoMark.PENDING }) { "Receipt claimed publication" }
        main { page.progress(mapOf("generated-240" to ReceiverByteProgress(100, 100, true, "complete"))) }
        main { adapter.notifyItemChanged(first) }; settle()
        check(main { photos.photoItems().first().mark == PhotoMark.NONE }) { "Old metadata rewound publication" }
        main { (list.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(38, 0) }; settle()
        val anchor = main { photos.photoItems()[page.firstVisible()].id }
        rows = rows.map { JSONObject(it.toString()).put("processing", "complete").put("receipt", "received") }
        runBlocking { model.refreshVisible("synthetic-response", page.firstVisible()) }; main { page.render(model.state.value) }; settle()
        check(main { photos.photoItems()[page.firstVisible()].id == anchor }) { "Refresh lost the visible photo" }
        runBlocking { model.more("synthetic-response"); model.more("synthetic-response") }; main { page.render(model.state.value) }; settle()
        check(main { photos.photoItems().map { it.id } == rows.reversed().map { it.getString("id") } }) { "Pagination lost order or duplicated a photo" }
        check(main { list.childCount < 100 }) { "Photos stopped virtualizing" }
        rows = rows + JSONObject(rows.last().toString()).put("cursor", 241).put("id", "generated-241").put("processing", "pending")
        runBlocking { model.refreshVisible("synthetic-response", 0) }; main { page.render(model.state.value) }; settle()
        check(model.state.value.counts == HistoryCounts(241, 240, 0))
        main { activity.receiverHome.history(model.state.value) }
        check(photoScope(model.state.value.counts, model.state.value.items, 0, emptyList()).saved == 240)
        runBlocking { model.select("synthetic-response", filter = "active", kind = "photo", sender = "fixture-phone") }
        check(model.state.value.items.single().id == "generated-241")
        check(queries.last().getString("state") == "active" && queries.last().getString("kind") == "photo" && queries.last().getString("sender_id") == "fixture-phone")
        rows = rows.map { JSONObject(it.toString()).put("processing", "complete") }
        runBlocking { model.refreshVisible("synthetic-response", 0) }
        check(model.state.value.filter == "active" && model.state.value.kind == "photo" && model.state.value.sender == "fixture-phone" && model.state.value.items.isEmpty())
        runBlocking { model.select("synthetic-response", filter = "all", kind = "all", sender = null) }
        main { page.render(model.state.value) }; settle()
        check(main { photos.photoItems().first().id == "generated-241" })
        main { activity.receiverHome.history(model.state.value) }
        check(main { views(activity.receiverHome.view).filterIsInstance<ImageView>().any { it.transitionName == photoTransitionName("generated-241") } }) { "Home mosaic missed the newly published photo" }
        return "PASS: current Photos live bytes without image reload/rewind; receipt and publication independent; 240-photo pagination/order/virtualization/anchor; counts and core state/kind/sender filters retained"
    } finally { main { activity.finish() }; ReceiverPreferences.setEnabled(targetContext, enabled); ReceiverEnvironment.previewImage = preview }
}
