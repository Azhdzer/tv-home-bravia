package com.mihir.tvhome;

import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.Closeable;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;

/**
 * Just enough of the ADB protocol to reach the TV's own adbd over loopback, so setup needs no
 * computer: with USB debugging on, adbd listens on port 5555 and answers 127.0.0.1 like anyone else,
 * asking "Allow USB debugging?" the first time. Nothing here ever leaves the TV.
 */
final class LocalAdb implements Closeable {

    private static final String HOST = "127.0.0.1";
    private static final int PORT = 5555;
    private static final int CONNECT_TIMEOUT_MS = 3000;
    private static final int APPROVAL_TIMEOUT_MS = 120_000; // someone has to answer the prompt with the remote
    private static final int COMMAND_TIMEOUT_MS = 120_000;
    private static final int MAX_PROMPTS = 3;
    private static final int MAX_MESSAGE = 1 << 20;

    private static final int A_CNXN = 0x4e584e43, A_AUTH = 0x48545541, A_OPEN = 0x4e45504f,
            A_OKAY = 0x59414b4f, A_CLSE = 0x45534c43, A_WRTE = 0x45545257;
    private static final int VERSION = 0x01000000;
    private static final int MAX_DATA = 256 * 1024;
    private static final int AUTH_TOKEN = 1, AUTH_SIGNATURE = 2, AUTH_RSAPUBLICKEY = 3;
    private static final byte[] NO_DATA = new byte[0];

    /** adbd signs and checks tokens as PKCS#1 v1.5 SHA-1, with the 20-byte token standing in for the digest. */
    private static final byte[] SHA1_DIGEST_INFO = {
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14};

    private final Socket socket;
    private final DataInputStream in;
    private final OutputStream out;
    private int nextLocalId = 1;

    private LocalAdb(Socket socket) throws IOException {
        this.socket = socket;
        in = new DataInputStream(socket.getInputStream());
        out = socket.getOutputStream();
    }

    /**
     * Connect and authenticate, keeping the key in keyDir so the TV only asks once.
     *
     * @throws java.net.ConnectException debugging is off
     * @throws java.net.SocketTimeoutException the prompt on the TV wasn't answered
     */
    static LocalAdb connect(File keyDir) throws IOException, GeneralSecurityException {
        Socket socket = new Socket();
        boolean ready = false;
        try {
            socket.connect(new InetSocketAddress(HOST, PORT), CONNECT_TIMEOUT_MS);
            socket.setSoTimeout(APPROVAL_TIMEOUT_MS);
            LocalAdb adb = new LocalAdb(socket);
            adb.handshake(loadOrCreateKey(keyDir));
            socket.setSoTimeout(COMMAND_TIMEOUT_MS);
            ready = true;
            return adb;
        } finally {
            if (!ready) socket.close();
        }
    }

    private void handshake(KeyPair key) throws IOException, GeneralSecurityException {
        send(A_CNXN, VERSION, MAX_DATA, "host::\0".getBytes(StandardCharsets.UTF_8));
        boolean signed = false;
        int prompts = 0;
        while (true) {
            Message m = read();
            if (m.command == A_CNXN) return;
            if (m.command != A_AUTH || m.arg0 != AUTH_TOKEN) throw new IOException("Unexpected ADB message during login");
            if (!signed) {
                signed = true;
                send(A_AUTH, AUTH_SIGNATURE, 0, sign(key.getPrivate(), m.data));
            } else {
                // The key isn't known yet: offering it is what makes the TV show its prompt.
                if (++prompts > MAX_PROMPTS) throw new IOException("Debugging was not allowed on the TV");
                send(A_AUTH, AUTH_RSAPUBLICKEY, 0, publicKeyMessage((RSAPublicKey) key.getPublic()));
            }
        }
    }

    /** Run one shell command as the shell user and return what it printed. */
    String shell(String command) throws IOException {
        int local = nextLocalId++;
        send(A_OPEN, local, 0, ("shell:" + command + "\0").getBytes(StandardCharsets.UTF_8));
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        while (true) {
            Message m = read();
            if (m.arg1 != local) continue; // the tail of an earlier command
            if (m.command == A_WRTE) {
                output.write(m.data);
                send(A_OKAY, local, m.arg0, NO_DATA);
            } else if (m.command == A_CLSE) {
                send(A_CLSE, local, m.arg0, NO_DATA);
                return new String(output.toByteArray(), StandardCharsets.UTF_8);
            } else if (m.command != A_OKAY) {
                throw new IOException("Unexpected ADB message during a command");
            }
        }
    }

    @Override
    public void close() throws IOException {
        socket.close();
    }

    // ---------------------------------------------------------------- wire format

    private static final class Message {
        final int command, arg0, arg1;
        final byte[] data;

        Message(int command, int arg0, int arg1, byte[] data) {
            this.command = command;
            this.arg0 = arg0;
            this.arg1 = arg1;
            this.data = data;
        }
    }

    private void send(int command, int arg0, int arg1, byte[] data) throws IOException {
        int checksum = 0;
        for (byte b : data) checksum += b & 0xFF;
        ByteBuffer header = ByteBuffer.allocate(24).order(ByteOrder.LITTLE_ENDIAN);
        header.putInt(command).putInt(arg0).putInt(arg1).putInt(data.length).putInt(checksum).putInt(~command);
        out.write(header.array());
        out.write(data);
        out.flush();
    }

    private Message read() throws IOException {
        byte[] raw = new byte[24];
        in.readFully(raw);
        ByteBuffer header = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN);
        int command = header.getInt(), arg0 = header.getInt(), arg1 = header.getInt(), length = header.getInt();
        if (length < 0 || length > MAX_MESSAGE) throw new IOException("Bad ADB message length");
        byte[] data = new byte[length];
        in.readFully(data);
        return new Message(command, arg0, arg1, data);
    }

    // ---------------------------------------------------------------- keys

    private static KeyPair loadOrCreateKey(File dir) throws IOException, GeneralSecurityException {
        File publicFile = new File(dir, "adbkey.pub");
        File privateFile = new File(dir, "adbkey");
        KeyFactory factory = KeyFactory.getInstance("RSA");
        if (publicFile.exists() && privateFile.exists()) {
            return new KeyPair(factory.generatePublic(new X509EncodedKeySpec(readFile(publicFile))),
                    factory.generatePrivate(new PKCS8EncodedKeySpec(readFile(privateFile))));
        }
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        KeyPair key = generator.generateKeyPair();
        writeFile(publicFile, key.getPublic().getEncoded());
        writeFile(privateFile, key.getPrivate().getEncoded());
        return key;
    }

    private static byte[] readFile(File file) throws IOException {
        try (DataInputStream stream = new DataInputStream(new FileInputStream(file))) {
            byte[] data = new byte[(int) file.length()];
            stream.readFully(data);
            return data;
        }
    }

    private static void writeFile(File file, byte[] data) throws IOException {
        try (FileOutputStream stream = new FileOutputStream(file)) {
            stream.write(data);
        }
    }

    private static byte[] sign(PrivateKey key, byte[] token) throws GeneralSecurityException {
        Signature signature = Signature.getInstance("NONEwithRSA");
        signature.initSign(key);
        signature.update(SHA1_DIGEST_INFO);
        signature.update(token);
        return signature.sign();
    }

    /** The key as adbd wants it: its own binary layout in base64, then a name for the prompt, NUL-terminated. */
    private static byte[] publicKeyMessage(RSAPublicKey key) {
        BigInteger modulus = key.getModulus();
        BigInteger word = BigInteger.ONE.shiftLeft(32);
        ByteBuffer encoded = ByteBuffer.allocate(4 + 4 + 256 + 256 + 4).order(ByteOrder.LITTLE_ENDIAN);
        encoded.putInt(64); // modulus size in 32-bit words
        encoded.putInt(modulus.mod(word).modInverse(word).negate().intValue()); // -1/n[0] mod 2^32
        putLittleEndian(encoded, modulus);
        putLittleEndian(encoded, BigInteger.ONE.shiftLeft(4096).mod(modulus)); // R^2 mod n
        encoded.putInt(key.getPublicExponent().intValue());
        String text = Base64.encodeToString(encoded.array(), Base64.NO_WRAP) + " tvhome@tv\0";
        return text.getBytes(StandardCharsets.UTF_8);
    }

    private static void putLittleEndian(ByteBuffer target, BigInteger value) {
        byte[] bigEndian = value.toByteArray(); // may carry a leading sign byte
        for (int i = 0; i < 256; i++) {
            int from = bigEndian.length - 1 - i;
            target.put(from >= 0 ? bigEndian[from] : 0);
        }
    }
}
