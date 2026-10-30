package com.mihir.tvhome;

import java.io.BufferedReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * What setup does to the TV, in the same safe order as launcher\build-and-install.ps1: the stock
 * launcher is only touched after the new one has started, and comes back if Home doesn't move.
 * Holds no Android classes, so it can be tested off the TV.
 */
final class HomeSetup {

    interface Shell { String run(String command) throws IOException; }
    interface Output { void say(int message, Object... args); }
    interface Store {
        String get(String key);
        void put(String key, String value);
    }
    /** Starts the new home screen for a moment. A crash there ends this process before Home is touched. */
    interface Trial { void run() throws InterruptedException; }

    private static final String SELF_PACKAGE = "com.mihir.tvhome";
    private static final String SELF_HOME = SELF_PACKAGE + "/.MainActivity";
    private static final String PLATFORM = "BRAVIA_ATV3_4K";
    private static final String DEFAULT_STOCK_HOME = "com.google.android.tvlauncher/.MainActivity";
    private static final Pattern STOCK_HOME =
            Pattern.compile("com\\.google\\.android\\.(tvlauncher|leanbacklauncher|apps\\.tv\\.launcherx)/.+");
    private static final String HOME_QUERY =
            "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME";
    private static final String SET_HOME = "cmd package set-home-activity --user 0 ";
    private static final String KEY_STOCK_HOME = "stock_home", KEY_ALREADY_OFF = "already_off";

    private final Shell shell;
    private final Output out;
    private final Store store;

    HomeSetup(Shell shell, Output out, Store store) {
        this.shell = shell;
        this.out = out;
        this.store = store;
    }

    /** Disable packages (none is fine) and make this launcher the home screen. True if it worked. */
    boolean install(List<String> packages, Trial trial) throws IOException, InterruptedException {
        String brand = prop("ro.product.manufacturer");
        if (!"Sony".equals(brand)) {
            out.say(R.string.setup_wrong_brand, brand);
            return false;
        }
        String platform = prop("ro.product.device");
        if (!PLATFORM.equals(platform)) out.say(R.string.setup_other_platform, platform, PLATFORM);

        String home = currentHome();
        boolean handOver = !SELF_HOME.equals(home);
        if (handOver && !STOCK_HOME.matcher(home).matches()) {
            out.say(R.string.setup_unknown_home, home);
            return false;
        }
        // Remember the TV as it was, once: a second run must not record our own changes as the original.
        if (handOver && store.get(KEY_STOCK_HOME) == null) {
            store.put(KEY_ALREADY_OFF, shell.run("pm list packages -d"));
            store.put(KEY_STOCK_HOME, home);
        }

        if (!packages.isEmpty()) disable(packages);
        shell.run("pm grant " + SELF_PACKAGE + " android.permission.ACCESS_FINE_LOCATION");

        out.say(R.string.setup_trying);
        trial.run();

        if (handOver) {
            // The stock launcher's HOME priority is 2: until it's disabled, this answers Success and does nothing.
            String stockPackage = packageOf(home);
            shell.run(SET_HOME + SELF_HOME);
            shell.run("pm disable-user --user 0 " + stockPackage);
            shell.run(SET_HOME + SELF_HOME);
            String now = currentHome();
            if (!SELF_HOME.equals(now)) {
                shell.run("pm enable " + stockPackage);
                shell.run(SET_HOME + home);
                out.say(R.string.setup_home_failed, now);
                return false;
            }
            clearStaleHome();
        }
        out.say(R.string.setup_done);
        return true;
    }

    /** Undo install(): packages that were already off before it stay off. True if Home went back. */
    boolean restore(List<String> packages) throws IOException {
        String stockHome = store.get(KEY_STOCK_HOME);
        if (stockHome == null) stockHome = DEFAULT_STOCK_HOME;
        Set<String> alreadyOff = listedPackages(store.get(KEY_ALREADY_OFF));
        for (String p : packages) {
            if (!alreadyOff.contains(p)) shell.run("pm enable " + p);
        }
        shell.run("pm enable " + packageOf(stockHome));
        shell.run(SET_HOME + stockHome);
        String now = currentHome();
        // By package: without a record stockHome is a guess, and the activity's name varies between firmwares.
        if (!now.startsWith(packageOf(stockHome) + "/")) {
            out.say(R.string.setup_restore_failed, now);
            return false;
        }
        clearStaleHome();
        out.say(R.string.setup_restored);
        return true;
    }

    /** Switching launchers leaves a stale home task in Settings that would make Home open behind other apps. */
    private void clearStaleHome() throws IOException {
        shell.run("am force-stop com.android.tv.settings");
    }

    private void disable(List<String> packages) throws IOException {
        int done = 0, missing = 0, failed = 0;
        // One pm per command: chained pm calls can silently stop after the first.
        for (String p : packages) {
            String result = shell.run("pm disable-user --user 0 " + p);
            if (result.contains("new state: disabled")) done++;
            else if (result.contains("Unknown package")) missing++;
            else failed++;
        }
        out.say(R.string.setup_disabled_summary, done, missing, failed);
    }

    private String prop(String name) throws IOException {
        return shell.run("getprop " + name).trim();
    }

    private String currentHome() throws IOException {
        String last = "";
        for (String line : shell.run(HOME_QUERY).split("\n")) {
            if (!line.trim().isEmpty()) last = line.trim();
        }
        return last;
    }

    private static String packageOf(String component) {
        return component.substring(0, component.indexOf('/'));
    }

    private static Set<String> listedPackages(String pmOutput) {
        Set<String> packages = new HashSet<>();
        if (pmOutput == null) return packages;
        for (String line : pmOutput.split("\n")) packages.add(line.trim().replace("package:", ""));
        return packages;
    }

    /** Packages from a debloat list: one per line, # starts a comment. */
    static List<String> readList(BufferedReader reader) throws IOException {
        List<String> packages = new ArrayList<>();
        for (String line = reader.readLine(); line != null; line = reader.readLine()) {
            int comment = line.indexOf('#');
            String p = (comment >= 0 ? line.substring(0, comment) : line).trim();
            if (!p.isEmpty()) packages.add(p);
        }
        return packages;
    }
}
