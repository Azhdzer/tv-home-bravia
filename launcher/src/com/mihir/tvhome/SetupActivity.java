package com.mihir.tvhome;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Set the TV up from the TV itself, for anyone without a computer on the TV's network: disables the
 * bloat and takes over Home through the TV's own ADB (see LocalAdb). Also the way back.
 */
public class SetupActivity extends Activity {

    private static final String KEY_TRIAL_RUNNING = "trial_running";

    private interface Action { boolean run(HomeSetup setup) throws IOException, InterruptedException; }

    private SharedPreferences prefs;
    private TextView log, openHome;
    private ScrollView logScroll;
    private boolean busy;

    private final HomeSetup.Store store = new HomeSetup.Store() {
        @Override public String get(String key) { return prefs.getString(key, null); }
        @Override public void put(String key, String value) { prefs.edit().putString(key, value).commit(); }
    };

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        prefs = getSharedPreferences("setup", MODE_PRIVATE);
        setContentView(buildUi());
        // We're only back here with this set if the trial took the whole app down.
        if (prefs.getBoolean(KEY_TRIAL_RUNNING, false)) {
            prefs.edit().putBoolean(KEY_TRIAL_RUNNING, false).commit();
            say(R.string.setup_trial_crashed);
        }
    }

    @Override
    public void onBackPressed() {
        if (!busy) super.onBackPressed();
    }

    // ---------------------------------------------------------------- layout

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setBackgroundColor(0xFF101012);
        root.setPadding(dp(48), dp(36), dp(48), dp(36));

        LinearLayout left = new LinearLayout(this);
        left.setOrientation(LinearLayout.VERTICAL);
        root.addView(left, new LinearLayout.LayoutParams(0, -1, 1f));

        TextView title = text(26, "sans-serif-light", Color.WHITE);
        title.setText(R.string.setup_title);
        left.addView(title);

        TextView intro = text(12, "sans-serif", 0xCCFFFFFF);
        intro.setText(R.string.setup_intro);
        intro.setLineSpacing(dp(3), 1f);
        LinearLayout.LayoutParams introParams = new LinearLayout.LayoutParams(-1, 0, 1f);
        introParams.setMargins(0, dp(12), 0, dp(12));
        left.addView(intro, introParams);

        View first = action(left, R.string.setup_install_clean, () -> runSetup(setup -> setup.install(debloatList(), this::tryLauncher)));
        action(left, R.string.setup_install_only, () -> runSetup(setup -> setup.install(Collections.<String>emptyList(), this::tryLauncher)));
        action(left, R.string.setup_restore, () -> runSetup(setup -> setup.restore(debloatList())));
        action(left, R.string.settings, () -> startActivity(new Intent(Settings.ACTION_SETTINGS)));
        openHome = action(left, R.string.setup_open_home, this::openHome);
        openHome.setVisibility(View.GONE);

        logScroll = new ScrollView(this);
        logScroll.setFocusable(false);
        GradientDrawable panel = new GradientDrawable();
        panel.setCornerRadius(dp(12));
        panel.setColor(0xFF1C1C1E);
        logScroll.setBackground(panel);
        log = text(12, "sans-serif", 0xE6FFFFFF);
        log.setPadding(dp(16), dp(14), dp(16), dp(14));
        log.setLineSpacing(dp(4), 1f);
        logScroll.addView(log);
        LinearLayout.LayoutParams logParams = new LinearLayout.LayoutParams(0, -1, 1f);
        logParams.setMargins(dp(24), 0, 0, 0);
        root.addView(logScroll, logParams);

        first.requestFocus();
        return root;
    }

    private TextView action(LinearLayout parent, int label, Runnable onClick) {
        TextView button = text(13, "sans-serif-medium", Color.WHITE);
        button.setText(label);
        button.setGravity(Gravity.CENTER_VERTICAL);
        button.setPadding(dp(16), 0, dp(16), 0);
        button.setFocusable(true);
        button.setClickable(true);
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(10));
        bg.setColor(0x26FFFFFF);
        button.setBackground(bg);
        button.setOnFocusChangeListener((v, has) -> {
            bg.setColor(has ? 0xF2FFFFFF : 0x26FFFFFF);
            button.setTextColor(has ? 0xFF111111 : Color.WHITE);
        });
        button.setOnClickListener(v -> { if (!busy) onClick.run(); });
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, dp(34));
        params.setMargins(0, dp(8), 0, 0);
        parent.addView(button, params);
        return button;
    }

    private TextView text(float sp, String family, int color) {
        TextView t = new TextView(this);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTypeface(Typeface.create(family, Typeface.NORMAL));
        t.setTextColor(color);
        return t;
    }

    private int dp(float v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    // ---------------------------------------------------------------- setup

    private void runSetup(Action action) {
        busy = true;
        openHome.setVisibility(View.GONE);
        say(R.string.setup_connecting);
        new Thread(() -> {
            boolean ok = false;
            try (LocalAdb adb = LocalAdb.connect(getFilesDir())) {
                ok = action.run(new HomeSetup(adb::shell, this::say, store));
            } catch (ConnectException e) {
                say(R.string.setup_adb_off);
            } catch (SocketTimeoutException | EOFException e) {
                say(R.string.setup_adb_not_approved);
            } catch (Exception e) {
                say(R.string.setup_error, String.valueOf(e));
            }
            boolean done = ok;
            runOnUiThread(() -> {
                busy = false;
                if (done) {
                    openHome.setVisibility(View.VISIBLE);
                    openHome.requestFocus();
                }
            });
        }).start();
    }

    /** Show the new home screen for a moment, then come back here. Runs on the setup thread. */
    private void tryLauncher() throws InterruptedException {
        prefs.edit().putBoolean(KEY_TRIAL_RUNNING, true).commit();
        startActivity(new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        Thread.sleep(3000);
        prefs.edit().putBoolean(KEY_TRIAL_RUNNING, false).commit();
        // Single task, so this also closes the trial.
        startActivity(new Intent(this, SetupActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    private void openHome() {
        startActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        finish();
    }

    private List<String> debloatList() throws IOException {
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(getAssets().open("debloat.txt"), StandardCharsets.UTF_8))) {
            return new ArrayList<>(HomeSetup.readList(reader));
        }
    }

    private void say(int message, Object... args) {
        String line = getString(message, args);
        runOnUiThread(() -> {
            log.append(line + "\n\n");
            logScroll.post(() -> logScroll.fullScroll(View.FOCUS_DOWN));
        });
    }
}
