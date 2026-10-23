package app.backupduck

/** Keep Chinese headline clauses together without prescribing a line count or changing the copy. */
internal fun displayHeadlineText(value: CharSequence): CharSequence {
    if (value.none { Character.UnicodeScript.of(it.code) == Character.UnicodeScript.HAN }) return value
    return buildString {
        val points = value.toString().replace("\u2060", "").codePoints().toArray()
        points.forEachIndexed { index, point ->
            appendCodePoint(point)
            if (index < points.lastIndex && point != '，'.code && point != '。'.code &&
                point != '\n'.code && points[index + 1] != '\n'.code) append('\u2060')
        }
    }
}
