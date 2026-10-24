package app.backupduck

import org.junit.Assert.*
import org.junit.Test

class ReceiverFirstRunTest {
    @Test fun backReachesWelcomeWithoutCompletingTheGuide() {
        var step: FirstRunStep? = FirstRunStep.SPACE
        val visited = mutableListOf<FirstRunStep>()
        while (step != null) { visited.add(step); step = step.previous }
        assertEquals(listOf(FirstRunStep.SPACE, FirstRunStep.GPHOTOS, FirstRunStep.CODE,
            FirstRunStep.RUNNING, FirstRunStep.WELCOME), visited)
        assertNull(FirstRunStep.WELCOME.previous)
    }

    @Test fun interruptedStepsResumeAndTransientSuccessIsNotReplayed() {
        FirstRunStep.entries.filter { it != FirstRunStep.CONNECTED }.forEach {
            assertEquals(it, FirstRunStep.restore(it.name))
        }
        assertEquals(FirstRunStep.GPHOTOS, FirstRunStep.restore("CONNECTED"))
        assertEquals(FirstRunStep.CODE, FirstRunStep.restore("code"))
        assertEquals(FirstRunStep.WELCOME, FirstRunStep.restore(null))
        assertEquals(FirstRunStep.WELCOME, FirstRunStep.restore("retired-step"))
    }
}
