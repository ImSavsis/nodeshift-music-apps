package space.nodeshift.music.core

import java.text.Normalizer
import java.util.Locale

object SequenceSimilarity {
    fun <T> ratio(a: List<T>, b: List<T>): Double {
        val total = a.size + b.size
        if (total == 0) {
            return 1.0
        }
        return 2.0 * matchingCount(a, b) / total
    }

    fun ratio(a: String, b: String): Double =
        ratio(a.codePoints().toArray().toList(), b.codePoints().toArray().toList())

    fun <T> matchingCount(a: List<T>, b: List<T>): Int {
        if (a.isEmpty() || b.isEmpty()) {
            return 0
        }
        val positions = HashMap<T, MutableList<Int>>()
        for ((index, element) in b.withIndex()) {
            positions.getOrPut(element) { mutableListOf() }.add(index)
        }
        var previous = IntArray(b.size + 1)
        var current = IntArray(b.size + 1)
        var previousTouched = ArrayList<Int>()
        var currentTouched = ArrayList<Int>()
        val stack = ArrayDeque<IntArray>()
        stack.addLast(intArrayOf(0, a.size, 0, b.size))
        var total = 0
        while (stack.isNotEmpty()) {
            val (alo, ahi, blo, bhi) = stack.removeLast()
            var bestI = alo
            var bestJ = blo
            var bestSize = 0
            for (i in alo until ahi) {
                currentTouched.clear()
                val hits = positions[a[i]]
                if (hits != null) {
                    for (j in hits) {
                        if (j < blo) continue
                        if (j >= bhi) break
                        val length = previous[j] + 1
                        current[j + 1] = length
                        currentTouched.add(j + 1)
                        if (length > bestSize) {
                            bestI = i - length + 1
                            bestJ = j - length + 1
                            bestSize = length
                        }
                    }
                }
                for (slot in previousTouched) previous[slot] = 0
                val swap = previous
                previous = current
                current = swap
                val swapTouched = previousTouched
                previousTouched = currentTouched
                currentTouched = swapTouched
            }
            for (slot in previousTouched) previous[slot] = 0
            previousTouched.clear()
            currentTouched.clear()
            if (bestSize > 0) {
                total += bestSize
                if (alo < bestI && blo < bestJ) {
                    stack.addLast(intArrayOf(alo, bestI, blo, bestJ))
                }
                if (bestI + bestSize < ahi && bestJ + bestSize < bhi) {
                    stack.addLast(intArrayOf(bestI + bestSize, ahi, bestJ + bestSize, bhi))
                }
            }
        }
        return total
    }
}

object TextMatching {
    private val bracketPattern = Regex("""[(\[][^)\]]*[)\]]""")
    private val nonWordPattern = Regex("""[^\p{L}\p{N}\p{M}_\s]""")
    private val marks = Regex("""\p{M}+""")
    private val whitespace = Regex("""[\s\p{Z}]+""")
    private val featuringPattern = Regex(
        """\s*[(\[]?\s*\b(?:feat|ft|featuring)\b\.?\s+.*$""",
        RegexOption.IGNORE_CASE,
    )
    private val artistSplitPattern = Regex(
        """\s*(?:,|;|&|/|(?<![\p{L}\p{N}_])[xX](?![\p{L}\p{N}_])|×|(?<![\p{L}\p{N}_])[aA][nN][dD](?![\p{L}\p{N}_])|(?<![\p{L}\p{N}_])[иИ](?![\p{L}\p{N}_]))\s*""",
    )

    private fun collapse(text: String): String =
        text.split(whitespace).filter { it.isNotEmpty() }.joinToString(" ")

    fun normalize(text: String): String {
        val folded = Normalizer.normalize(text, Normalizer.Form.NFKD)
            .replace(marks, "")
            .lowercase(Locale.ROOT)
        val withoutBrackets = bracketPattern.replace(folded, " ")
        return collapse(nonWordPattern.replace(withoutBrackets, " "))
    }

    fun stripFeaturing(text: String): String = collapse(featuringPattern.replace(text, ""))

    fun titleKey(title: String): String = normalize(stripFeaturing(title))

    fun artistKey(artist: String): String = normalize(stripFeaturing(artist))

    fun artistParts(artist: String): List<String> =
        artistSplitPattern.split(stripFeaturing(artist)).map(::normalize).filter { it.isNotEmpty() }

    fun titleRatio(a: String, b: String): Double = SequenceSimilarity.ratio(titleKey(a), titleKey(b))

    fun artistRatio(a: String, b: String): Double {
        val whole = SequenceSimilarity.ratio(artistKey(a), artistKey(b))
        if (whole >= 0.999) {
            return whole
        }
        var best = whole
        for (x in artistParts(a)) {
            for (y in artistParts(b)) {
                best = maxOf(best, SequenceSimilarity.ratio(x, y))
            }
        }
        return best
    }

    fun words(text: String): List<String> = text.split(whitespace).filter { it.isNotEmpty() }
}
