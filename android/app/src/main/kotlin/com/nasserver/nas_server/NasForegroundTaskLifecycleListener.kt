package com.nasserver.nas_server

import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine

class NasForegroundTaskLifecycleListener(
    private val application: NasServerApplication,
) : FlutterForegroundTaskLifecycleListener {
    override fun onEngineCreate(flutterEngine: FlutterEngine?) {
        flutterEngine?.let(application::registerBackgroundFlutterEngine)
    }

    override fun onTaskStart(starter: FlutterForegroundTaskStarter) = Unit

    override fun onTaskRepeatEvent() = Unit

    override fun onTaskDestroy() = Unit

    override fun onEngineWillDestroy() = Unit
}
