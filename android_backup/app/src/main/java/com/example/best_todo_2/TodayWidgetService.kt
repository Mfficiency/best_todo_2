package com.example.best_todo_2

import android.content.Intent
import android.widget.RemoteViewsService

class TodayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodayWidgetFactory(applicationContext)
    }
}
