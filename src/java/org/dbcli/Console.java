package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import org.jline.builtins.Commands;
import org.jline.builtins.Source;
import org.jline.keymap.KeyMap;
import org.jline.reader.*;
import org.jline.reader.impl.DefaultParser;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.terminal.impl.AbstractTerminal;
import org.jline.utils.*;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import static org.jline.reader.LineReader.DISABLE_HISTORY;
import static org.jline.reader.LineReader.SECONDARY_PROMPT_PATTERN;
import static org.jline.terminal.impl.AbstractWindowsTerminal.TYPE_WINDOWS;
import static org.jline.terminal.impl.AbstractWindowsTerminal.TYPE_WINDOWS_256_COLOR;


public final class Console {
    public final static Pattern ansiPattern = Pattern.compile("^\33\\[[\\d\\;]*[mK]$");
    public static Output writer;
    public static NonBlockingReader input;
    public static String charset = System.getProperty("sun.stdout.encoding");
    public static ClassAccess<LineReaderImpl> accessor = ClassAccess.access(LineReaderImpl.class);
    protected static ScheduledExecutorService threadPool = Executors.newScheduledThreadPool(6);
    public AbstractTerminal terminal;
    public boolean isSubSystem = false;
    LineReaderImpl reader;
    Less.Play display;
    long threadID;
    HashMap<String, Candidate[]> candidates = new HashMap<>(1024);
    MyCompleter completer = new MyCompleter(this);
    boolean isPrompt = true;
    boolean isJansiConsole = false;
    ArrayList<AttributedString> titles = new ArrayList<>(2);
    ArrayList<AttributedString> tmpTitles = new ArrayList<>(2);
    private LuaState lua;
    volatile private ScheduledFuture task;
    private ActionListener event;
    private char[] keys;
    private EventCallback callback;
    private ParserCallback parserCallback;
    MyParser parser;
    private volatile boolean pause = false;
    private MyHistory history = new MyHistory();

    private Status status;
    private String colorPlan;
    private KeyMap keyMap;

    public Console(String historyLog) throws Exception {
        colorPlan = "dbcli";
        if (OSUtils.IS_WINDOWS && !(OSUtils.IS_CYGWIN || OSUtils.IS_MSYSTEM))
            this.terminal = JansiWinSysTerminal.createTerminal(colorPlan, null, ("ansicon").equals(System.getenv("ANSICON_DEF")) || OSUtils.IS_CONEMU, null, 0, true, Terminal.SignalHandler.SIG_IGN, false);
        else
            this.terminal = (AbstractTerminal) TerminalBuilder.builder().system(true).name(colorPlan).jna(false).jansi(true).signalHandler(Terminal.SignalHandler.SIG_IGN).nativeSignals(true).build();
        Interrupter.reset();
        Interrupter.handler = terminal.handle(Terminal.Signal.INT, new Interrupter());
        this.status = this.terminal.getStatus();
        this.display = new Less.Play(this.terminal);
        this.reader = (LineReaderImpl) LineReaderBuilder.builder().terminal(terminal).appName("dbcli").build();
        this.parser = new MyParser();
        this.reader.setParser(parser);
        this.reader.setHighlighter(parser);
        this.reader.setCompleter(completer);
        this.reader.setHistory(history);
        this.reader.unsetOpt(LineReader.Option.MOUSE);
        this.reader.setOpt(LineReader.Option.DELAY_LINE_WRAP);
        this.reader.setOpt(LineReader.Option.DISABLE_EVENT_EXPANSION);
        this.reader.setOpt(LineReader.Option.CASE_INSENSITIVE);
        this.reader.setOpt(LineReader.Option.CASE_INSENSITIVE_SEARCH);
        this.reader.setOpt(LineReader.Option.AUTO_FRESH_LINE);
        this.reader.setOpt(LineReader.Option.LIST_ROWS_FIRST);
        this.reader.setOpt(LineReader.Option.INSERT_TAB);
        this.reader.setVariable(DISABLE_HISTORY, true);
        this.reader.setVariable(LineReader.HISTORY_FILE, historyLog);
        this.reader.setVariable(LineReader.HISTORY_FILE_SIZE, 2000);
        this.isJansiConsole = this.terminal instanceof JansiWinSysTerminal;
        //terminal.echo(false); //fix paste issue of iTerm2 when past is off
        enableBracketedPaste("on");
        keyMap = reader.getKeyMaps().get(LineReader.MAIN);
        for (String s : new String[]{"^_", "^[^H"}) setKeyCode(LineReader.BACKWARD_KILL_WORD, s);
        //deal with keys ctrl+arrow and alt+Arrow
        for (String s : new String[]{"^[[", "[1;2", "[1;3", "[1;5"}) {
            setKeyCode(LineReader.UP_HISTORY, "^[" + s + "A");
            setKeyCode(LineReader.DOWN_HISTORY, "^[" + s + "B");
            setKeyCode(LineReader.FORWARD_WORD, "^[" + s + "C");
            setKeyCode(LineReader.BACKWARD_WORD, "^[" + s + "D");
        }
        //alt+y and alt+z
        setKeyCode("redo", "^[y");
        setKeyCode("undo", "^[z");

        input = terminal.reader();
        writer = new Output(terminal.writer());
        colorPlan = terminal.getType();
        threadID = Thread.currentThread().getId();

        callback = new EventCallback() {
            @Override
            public void call(Object... c) {
                if (cancelSeq == 0) ++cancelSeq;
                if (!pause && lua != null && threadID == Thread.currentThread().getId()) {
                    lua.getGlobal("TRIGGER_EVENT");
                    Integer r = (Integer) (lua.call(c)[0]);
                    if (r == 2) ((long[]) c[0])[0] = 2;
                } else if (event != null) {
                    if (c[1] instanceof ActionEvent) event.actionPerformed((ActionEvent) c[0]);
                    else event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, "\3"));
                }
                if (titles.size() > 0)
                    new Thread(() -> {
                        try {
                            Thread.sleep(1000);
                        } catch (InterruptedException e) {
                        }
                        setStatus("flush", null);
                        reader.redrawLine();
                    }).start();
            }
        };
        Interrupter.listen(this, callback);
    }

    public void initDisplay() {
        display.init(false);
    }

    public void exitDisplay() {
        display.exit();
    }

    public void display(String[] args) {
        display.updateAnsi(Arrays.asList(args), -1);
    }


    public void enableMouse(String val) {
        if ("off".equals(val)) reader.unsetOpt(LineReader.Option.MOUSE);
        else reader.setOpt(LineReader.Option.MOUSE);
    }

    public void enableBracketedPaste(String val) {
        if ("off".equals(val)) reader.unsetOpt(LineReader.Option.BRACKETED_PASTE);
        else reader.setOpt(LineReader.Option.BRACKETED_PASTE);
        if (isJansiConsole) ((JansiWinSysTerminal) terminal).enablePaste(!"off".equals(val));
    }


    public void setLua(LuaState lua) {
        this.lua = lua;
        parserCallback = null;
    }

    public String ulen(String s, final int maxLength) {
        if (s == null) return "0:0";
        AttributedString buff = AttributedString.fromAnsi(s);
        int size = buff.columnLength();
        if (maxLength > 0 && maxLength < size) {
            buff = buff.columnSubSequence(0, maxLength);
            s = buff.toAnsi(terminal);
            size = maxLength;
        }
        return s.getBytes().length + ":" + size + ":" + (maxLength > 0 ? s : "");
    }

    private Candidate candidate(String key, String desc) {
        if (desc != null && (desc.equals("") || desc.equals("\0"))) desc = null;
        return new Candidate(key, key, null, null, null, null, true);
    }

    public void addCompleters(Map<String, ?> keys, boolean isCommand) {
        Candidate c = isCommand ? candidate("", null) : null;
        for (Map.Entry<String, ?> entry : keys.entrySet()) {
            String key = entry.getKey().trim().toUpperCase();
            Object value = entry.getValue();
            String desc = value instanceof Map ? "\0" : value instanceof String ? (String) value : "";
            Candidate[] cs = candidates.get(key);
            if (cs == null || isCommand && (cs[2] == null || cs[2].descr() == null)) {
                candidates.put(key, new Candidate[]{candidate(key, desc), candidate(key.toLowerCase(), desc), c});
                int index = key.lastIndexOf(".");
                if (index > 0) {
                    key = key.substring(index + 1);
                    candidates.put(key, new Candidate[]{candidate(key, desc), candidate(key.toLowerCase(), desc), c});
                }
            }
            if ("\0".equals(desc)) {
                for (Map.Entry<String, String> e : ((Map<String, String>) entry.getValue()).entrySet()) {
                    String k = e.getKey().trim().toUpperCase();
                    desc = e.getValue();
                    candidates.put(key + " " + k, new Candidate[]{candidate(k, desc), candidate(k.toLowerCase(), desc), c});
                }
            }
        }
    }

    public void setKeywords(Map<String, ?> keywords) {
        parser.keywords = keywords;
        completer.setKeysWords(keywords);
        //addCompleters(keywords, false);
    }

    public void setCommands(Map<String, Object> commands) {
        parser.commands = commands;
        completer.setCommands(commands);
        //addCompleters(commands, true);
    }

    public void setSubCommands(Map<String, Object> commands) {
        addCompleters(commands, true);
        completer.setCommands(commands);
        //parser.commands.putAll(commands);
    }

    public String getPlatform() {
        if (OSUtils.IS_CYGWIN) return "cygwin";
        if (OSUtils.IS_MSYSTEM) return "mingw";
        if (OSUtils.IS_CONEMU) return "conemu";
        if (OSUtils.IS_OSX) return "mac";
        if (OSUtils.IS_WINDOWS) return "windows";
        return "linux";
    }

    public void setStatus(String status, String color) {
        if (colorPlan.equals(TYPE_WINDOWS_256_COLOR) || colorPlan.equals(TYPE_WINDOWS) || getScreenWidth() <= 0) return;
        if (tmpTitles.size() == 0) {
            tmpTitles.add(AttributedString.fromAnsi(new String(new char[getScreenWidth() - 1]).replace('\0', ' ')));
            tmpTitles.add(tmpTitles.get(0));
        }
        this.status.update(tmpTitles);
        if ("flush".equals(status)) this.status.update(titles);
        else {
            AttributedString sep = titles.size() != 0 ? titles.get(0) : AttributedString.fromAnsi(color + new String(new char[getScreenWidth() - 1]).replace('\0', '-'));
            titles.clear();
            if (status != null && !status.equals("")) {
                titles.add(sep);
                AttributedStringBuilder asb = new AttributedStringBuilder();
                asb.ansiAppend(status);
                titles.add(asb.toAttributedString());
            }
            this.status.update(titles);
        }
    }

    public int getBufferWidth() {
        if ("terminator".equals(System.getenv("TERM"))) return 2000;
        return terminal.getBufferSize().getColumns();
    }

    public int getScreenWidth() {
        return terminal.getWidth();
    }

    public int getScreenHeight() {
        if (OSUtils.IS_WINDOWS && !(OSUtils.IS_CYGWIN || OSUtils.IS_MSYSTEM)) {
            return terminal.getHeight();
        }
        return terminal.getHeight() - titles.size();
    }


    public int wcwidth(String str) {
        if (str == null || str.equals("")) return 0;
        return display.wcwidth(str);
    }

    public void less(String output, int titleLines, int spaces, int lines) throws Exception {
        Source source = new Source() {
            @Override
            public String getName() {
                return "";
            }

            @Override
            public InputStream read() throws IOException {
                return new ByteArrayInputStream(output.getBytes());
            }

            @Override
            public Long lines() {
                return null;
            }
        };
        Less less = new Less(terminal);
        less.noInit = true;
        less.veryQuiet = true;
        less.padding = spaces;
        less.numWidth = (int) Math.max(3, Math.ceil(Math.log10(lines < 10 ? 10 : lines)));
        less.setTitleLines(titleLines);
        less.chopLongLines = true;
        less.quitIfOneScreen = true;
        less.ignoreCaseAlways = true;
        less.run(source);
    }

    public PrintWriter getOutput() {
        return writer;
    }

    public void write(String msg) {
        if (writer == null) return;
        writer.write(msg);
        writer.flush();
    }

    public void println(String msg) {
        if (writer == null) return;
        writer.println(msg);
    }

    public Object invokeMethod(String method, Object... o) {
        return accessor.invoke(reader, method, o);
    }

    public int cancelSeq = 0;
    private String currentBuffer;

    public String readLine(String prompt, String buffer) {
        try {
            if (cancelSeq >= 5) System.exit(0);
            setEvents(null, null);
            terminal.echo(false);
            terminal.resume();
            isPrompt = buffer != null && ansiPattern.matcher(buffer).find();
            if (isPrompt) {
                parser.setAnsi(buffer);
                buffer = null;
            }
            pause = false;
            currentBuffer = buffer;
            String line = reader.readLine(prompt, null, buffer);
            if (line != null) {
                line = parser.getLines();
                if (line == null) return readLine(parser.secondPrompt, null);
            }
            cancelSeq *= 0;
            if (pause) {
                terminal.echo(true);
                terminal.pause();
            } else {
                pause = true;
            }
            return line;
        } catch (UserInterruptException | EndOfFileException e) {
            ++cancelSeq;
            terminal.puts(InfoCmp.Capability.cursor_up);
            terminal.puts(InfoCmp.Capability.delete_line);
            terminal.raise(Terminal.Signal.INT);
            status.redraw();
            return "";
        } finally {

        }
    }

    public String readLine(String prompt) {
        return readLine(prompt, null);
    }

    public String readLine() {
        return readLine(null, null);
    }

    public Boolean isRunning() {
        return pause;
    }

    public int setLastHistory() {
        return history.setIndex();
    }

    public void updateLastHistory(String line) {
        history.updateLast(line);
    }

    public synchronized void setEvents(ActionListener event, char[] keys) {
        this.event = event;
        this.keys = keys;
        if (this.task != null) {
            this.task.cancel(true);
            this.task = null;
        }
        if (this.event != null && this.keys != null) {
            //this.task = this.threadPool.scheduleWithFixedDelay(this.monitor, 1000, 200, TimeUnit.MILLISECONDS);
        }
    }

    public void setEvents() {
        setEvents(null, null);
    }

    public String getKeyMap(String[] options) throws Exception {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        Commands.keymap(reader, new PrintStream(stream), System.err, options);
        return stream.toString();
    }

    public String setKeyCode(String keyEvent, String keyCode) throws IOException {
        String keySeq;
        if (keyCode == null) {
            write("Input key code for '" + keyEvent + "'(hit Enter to complete): ");
            int c;
            StringBuilder sb = new StringBuilder();
            boolean isPause = terminal.paused();
            if (isPause) terminal.resume();
            while (true) {
                c = terminal.reader().read();
                if (c > 0) {
                    if (c == 10 || c == 13) break;
                    sb.appendCodePoint(c);
                }
            }
            if (isPause) terminal.pause();
            keySeq = sb.toString();
            keyCode = KeyMap.display(keySeq);
            write(keyCode + "\n");
        } else keySeq = KeyMap.translate(keyCode);
        if (keyCode.equals("")) return keyCode;
        keyMap.unbind(keySeq);
        keyMap.bind(new Reference(keyEvent), keySeq);
        return keyCode;
    }

    interface ParserCallback {
        Object[] call(Object... e);
    }

    class MyParser extends DefaultParser implements Highlighter {
        public static final String DEFAULT_HIGHLIGHTER_COLORS = "rs=1:st=2:nu=3:co=4:va=5:vn=6:fu=7:bf=8:re=9";
        public final Pattern numPattern = Pattern.compile("([0-9]+)");
        final String NOR = "\033[0m";
        public String buffer = null;
        public Map<String, String> colors = Arrays.stream(DEFAULT_HIGHLIGHTER_COLORS.split(":"))
                .collect(Collectors.toMap(s -> s.substring(0, s.indexOf('=')),
                        s -> s.substring(s.indexOf('=') + 1)));
        public Map<String, ?> keywords = new HashMap();
        public Map<String, Object> commands = new HashMap();
        volatile String secondPrompt = "    ";
        volatile int lines = 0;
        StringBuffer sb = new StringBuffer(32767);
        boolean enabled = true;
        Pattern p1 = Pattern.compile("^(\\s*\\.?)([^\\s\\|;/]+)(.*)$", Pattern.DOTALL);
        AttributedStringBuilder asb = new AttributedStringBuilder();
        final AttributedString empty = asb.toAttributedString();
        private String ansi = null;
        private String errorAnsi = null;
        private volatile String prev = null;
        private volatile int sub = 0;

        public MyParser() {
            super();
            setAnsi(NOR);
            super.setEofOnEscapedNewLine(true);
            reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
            Interrupter.listen(MyParser.this, c -> {
                lines = 0;
                sb.setLength(0);
            });
        }

        public final String getLines() {
            if (lines < 0) ++lines;
            return lines > 0 ? null : sb.toString();
        }

        public final ParsedLine parse(final String line, final int cursor, final ParseContext context) {
            if (!isPrompt && line == null) return null;
            if (Thread.currentThread().isInterrupted()) return super.parse("", 0, context);
            if (context == ParseContext.COMPLETE) return super.parse(line, cursor, context);
            if (context != ParseContext.ACCEPT_LINE) return null;

            if (lines <= 0) sb.setLength(0);
            else sb.append('\n');
            sb.append(line);

            if (parserCallback == null) {
                lua.load("return {call=env.parse_line}", "proxy");
                lua.call(0, 1);
                parserCallback = lua.getProxy(-1, ParserCallback.class);
                lua.pop(1);
            }

            Object[] result = parserCallback.call(line);
            lines += (int) result[3];
            if ((Boolean) result[0]) {
                if (result.length > 1 && !secondPrompt.equals(result[1])) {
                    secondPrompt = (String) result[1];
                    reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
                }
                return null;
            }
            if (lines <= terminal.getHeight() - 10 && currentBuffer == null) {
                reader.setVariable(DISABLE_HISTORY, false);
                history.add(sb.toString());
                reader.setVariable(DISABLE_HISTORY, true);
            }
            lines = 0;
            if ((Boolean) result[2]) {
                pause = true;
            }
            return null;
        }


        public final void setAnsi(final String ansi) {
            if (ansi.equals(this.ansi)) return;
            this.ansi = ansi;
            Matcher m = numPattern.matcher(ansi);
            m.find();
            this.errorAnsi = Integer.valueOf(m.group(1)) > 50 ? "\33[91m" : "\33[31m";
            enabled = !ansi.equals(NOR);
            for (String key : colors.keySet()) {
                String value;
                switch (key) {
                    case "bf":
                        value = "\33[91m";
                        break;
                    case "fu":
                        value = ansi;
                        break;
                    case "rs":
                        value = "\33[95m";
                        break;
                    default:
                        value = ansi;
                        break;
                }
                colors.put(key, value);
            }
        }

        private final AttributedStringBuilder process(final String buffer, final int index) {
            char c;
            boolean found;
            if (!enabled) asb.append(buffer);
            else {
                final int n = buffer.length();
                if (n > 2048) {
                    asb.append(buffer);
                    return asb;
                }
                for (int i = index; i < n; i++) {
                    c = buffer.charAt(i);
                    found = c == '(' || c == ')' || c == '{' || c == '}' || c == ',';
                    if (found) asb.ansiAppend(NOR);
                    asb.append(c);
                    if (found) asb.ansiAppend(ansi);
                }
            }
            return asb;
        }

        public final AttributedString highlight(final LineReader reader, final String buffer) {
            try {
                final int len = buffer.length();
                if (sub > 0 && len >= sub && buffer.startsWith(prev)) {
                    if (len > sub) {
                        process(buffer, sub);
                        sub = len;
                        prev = buffer;
                    }
                    return asb.toAttributedString();
                }
                sub *= 0;
                prev = null;
                asb.setLength(0);

                if (len == 0) {
                    return empty;
                } else if (buffer.charAt(0) == '\33') {
                    asb.ansiAppend(buffer);
                } else if (!enabled) {
                    asb.ansiAppend(ansi).append(buffer);
                } else {
                    if (Console.this.isSubSystem || lines != 0) {
                        asb.ansiAppend(ansi);
                        process(buffer, 0);
                        sub = len;
                        prev = buffer;
                    } else {
                        //Handling command name
                        final Matcher m = p1.matcher(buffer);
                        if (m.find()) {
                            asb.ansiAppend(NOR);
                            if (!commands.containsKey(m.group(2).toUpperCase())) {
                                asb.ansiAppend(m.group(1)).ansiAppend(errorAnsi).append(m.group(2)).ansiAppend(ansi);
                                process(m.group(3), 0);
                            } else {
                                asb.ansiAppend(ansi);
                                process(buffer, 0);
                            }
                            if (!m.group(3).equals("")) {
                                prev = buffer;
                                sub = len;
                            }
                        } else process(buffer, 0);
                    }
                }
                return asb.toAttributedString();
            } catch (Exception e) {
                e.printStackTrace();
                throw e;
            } finally {

            }
        }

        @Override
        public void setErrorPattern(Pattern errorPattern) {

        }

        @Override
        public void setErrorIndex(int errorIndex) {

        }
    }
}