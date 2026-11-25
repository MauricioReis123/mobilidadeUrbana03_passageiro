package com.omni.passageiro;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;

/**
 * Inicializa automaticamente o canal de notificações de alta prioridade (`omni_passenger_campaigns_high`)
 * no Android 8.0+ sem exigir coreLibraryDesugaring ou plugins externos de build Gradle.
 */
public class OmniNotificationChannelProvider extends ContentProvider {

    public static final String CHANNEL_ID = "omni_passenger_campaigns_high";
    public static final String CHANNEL_NAME = "Campanhas & Cupons OMNI";
    public static final String CHANNEL_DESC =
            "Alertas promocionais de corrida e descontos exclusivos para passageiros.";

    @Override
    public boolean onCreate() {
        Context context = getContext();
        if (context != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                NotificationManager manager =
                        (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
                if (manager != null) {
                    NotificationChannel channel = new NotificationChannel(
                            CHANNEL_ID,
                            CHANNEL_NAME,
                            NotificationManager.IMPORTANCE_HIGH
                    );
                    channel.setDescription(CHANNEL_DESC);
                    channel.enableVibration(true);
                    channel.setShowBadge(true);

                    Uri soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
                    if (soundUri != null) {
                        AudioAttributes attrs = new AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build();
                        channel.setSound(soundUri, attrs);
                    }
                    manager.createNotificationChannel(channel);
                }
            } catch (Throwable ignored) {
                // Falha isolada na criação do canal não impede inicialização do app
            }
        }
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}
