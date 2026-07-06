package com.nasserver.nas_server

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(NasServerApplication.ENGINE_ID)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        (application as? NasServerApplication)?.registerMainFlutterEngine(flutterEngine)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return false
    }
}
