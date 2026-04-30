import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SimpleNoteApp());
}

// --- Note Model ---
class Note {
  final int? id;
  final String title;
  final String content;

  Note({this.id, required this.title, required this.content});

  Map<String, dynamic> toMap() => {'id': id, 'title': title, 'content': content};

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'],
        title: map['title'],
        content: map['content'],
      );
}

// --- Simple Database Helper ---
class DatabaseHelper {
  static Database? _db;

  static Future<void> _init() async {
    if (kIsWeb || _db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'simple_notes.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, v) {
      return db.execute('CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT)');
    });
  }

  static Future<List<Note>> getNotes() async {
    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final data = prefs.getString('notes') ?? '[]';
        final List decoded = jsonDecode(data);
        return decoded.map((e) => Note.fromMap(Map<String, dynamic>.from(e))).toList();
      } catch (e) {
        debugPrint('Error getting notes: $e');
        return [];
      }
    }
    await _init();
    final List<Map<String, dynamic>> maps = await _db!.query('notes', orderBy: 'id DESC');
    return maps.map((e) => Note.fromMap(e)).toList();
  }

  static Future<void> addNote(Note note) async {
    if (kIsWeb) {
      try {
        final notes = await getNotes();
        final newNote = Note(
          id: DateTime.now().millisecondsSinceEpoch,
          title: note.title,
          content: note.content,
        );
        notes.insert(0, newNote);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('notes', jsonEncode(notes.map((e) => e.toMap()).toList()));
      } catch (e) {
        debugPrint('Error adding note: $e');
      }
      return;
    }
    await _init();
    await _db!.insert('notes', {'title': note.title, 'content': note.content});
  }

  static Future<void> updateNote(Note note) async {
    if (kIsWeb) {
      try {
        final notes = await getNotes();
        final index = notes.indexWhere((e) => e.id == note.id);
        if (index != -1) {
          notes[index] = note;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('notes', jsonEncode(notes.map((e) => e.toMap()).toList()));
        }
      } catch (e) {
        debugPrint('Error updating note: $e');
      }
      return;
    }
    await _init();
    await _db!.update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  static Future<void> deleteNote(int id) async {
    if (kIsWeb) {
      try {
        final notes = await getNotes();
        notes.removeWhere((e) => e.id == id);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('notes', jsonEncode(notes.map((e) => e.toMap()).toList()));
      } catch (e) {
        debugPrint('Error deleting note: $e');
      }
      return;
    }
    await _init();
    await _db!.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}

// --- UI Layer ---
class SimpleNoteApp extends StatelessWidget {
  const SimpleNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const NotesScreen(),
    );
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() async {
    final data = await DatabaseHelper.getNotes();
    setState(() => _notes = data);
  }

  void _showForm(Note? note) {
    final tController = TextEditingController(text: note?.title);
    final cController = TextEditingController(text: note?.content);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: tController, decoration: const InputDecoration(hintText: 'Title')),
            TextField(controller: cController, decoration: const InputDecoration(hintText: 'Content')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (note == null) {
                  await DatabaseHelper.addNote(Note(title: tController.text, content: cController.text));
                } else {
                  await DatabaseHelper.updateNote(Note(id: note.id, title: tController.text, content: cController.text));
                }
                if (mounted) {
                  Navigator.pop(context);
                  _refresh();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(note == null ? 'Note Added' : 'Note Updated')),
                  );
                }
              },
              child: Text(note == null ? 'Add Note' : 'Update'),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simple Notes')),
      body: _notes.isEmpty
          ? const Center(child: Text('No notes yet'))
          : ListView.builder(
              itemCount: _notes.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(_notes[i].title),
                subtitle: Text(_notes[i].content),
                onTap: () => _showForm(_notes[i]),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await DatabaseHelper.deleteNote(_notes[i].id!);
                    _refresh();
                  },
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}
