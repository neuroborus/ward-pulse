package app.wardpulse.wear.complication

import android.content.Context
import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import app.wardpulse.wear.R

class DebugRangedComplicationDataSourceService : SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? =
        if (request.complicationType == ComplicationType.RANGED_VALUE) debugRangedComplicationData() else null

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.RANGED_VALUE) debugRangedComplicationData() else null
}

class DebugMonoComplicationDataSourceService : SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? =
        if (request.complicationType == ComplicationType.MONOCHROMATIC_IMAGE) debugMonoComplicationData(this) else null

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.MONOCHROMATIC_IMAGE) debugMonoComplicationData(this) else null
}

internal fun debugRangedComplicationData(): RangedValueComplicationData =
    RangedValueComplicationData.Builder(
        value = 4f,
        min = 0f,
        max = 10f,
        contentDescription = PlainComplicationText.Builder("QA ranged fixture").build(),
    ).setValueType(RangedValueComplicationData.TYPE_UNDEFINED)
        .setTitle(PlainComplicationText.Builder("Probe").build())
        .build()

internal fun debugMonoComplicationData(context: Context): MonochromaticImageComplicationData =
    MonochromaticImageComplicationData.Builder(
        monochromaticImage = MonochromaticImage.Builder(
            Icon.createWithResource(context, R.drawable.ic_complication).setTint(0xFFFF00FF.toInt()),
        ).build(),
        contentDescription = PlainComplicationText.Builder("QA monochromatic fixture").build(),
    ).build()
