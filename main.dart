// lib/main.dart
// PlanetSport - Integrado (registro, perfil, posts, foros, memes, chat, juegos, llamadas)
// IMPORTANTE: Configurar Firebase (google-services.json) y dependencias en pubspec.yaml.

import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// MAIN
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(PlanetSportApp());
}

class PlanetSportApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthService>(
      create: (_) => AuthService(),
      child: MaterialApp(
        title: 'PlanetSport',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: AuthWrapper(),
      ),
    );
  }
}

/* --------------------------
   AuthService: maneja estado
   -------------------------- */
class AuthService extends ChangeNotifier {
  User? user;
  Map<String, dynamic>? profile;

  AuthService() {
    FirebaseAuth.instance.authStateChanges().listen((u) async {
      user = u;
      if (u != null) {
        final snap = await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
        profile = snap.exists ? snap.data() : null;
      } else {
        profile = null;
      }
      notifyListeners();
    });
  }
}

/* --------------------------
   AuthWrapper: decide pantalla
   -------------------------- */
class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    if (auth.user == null) return SignInScreen();
    return MainScreen();
  }
}

/* --------------------------
   SignIn / Register
   -------------------------- */
class SignInScreen extends StatefulWidget {
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool isRegister = false;
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  DateTime? _birth;
  bool _loading = false;

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 14),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birth = picked);
  }

  bool _isOldEnough(DateTime birth) {
    final today = DateTime.now();
    final age = today.year - birth.year - ((today.month < birth.month || (today.month == birth.month && today.day < birth.day)) ? 1 : 0);
    return age >= 12;
  }

  Future<void> _register() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    final confirm = _confirm.text;
    if (email.isEmpty || pass.isEmpty || confirm.isEmpty || _birth == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Completá todos los campos')));
      return;
    }
    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Contraseñas no coinciden')));
      return;
    }
    if (!_isOldEnough(_birth!)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Debés tener 12 años o más')));
      return;
    }
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'birth': Timestamp.fromDate(_birth!),
        'username': email.split('@').first,
        'accountType': 'personal',
        'photoUrl': null,
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Completá email y contraseña')));
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pass);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Text('PlanetSport', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              TextField(controller: _email, decoration: InputDecoration(labelText: 'Email')),
              SizedBox(height: 8),
              TextField(controller: _pass, decoration: InputDecoration(labelText: 'Contraseña'), obscureText: true),
              if (isRegister) ...[
                SizedBox(height: 8),
                TextField(controller: _confirm, decoration: InputDecoration(labelText: 'Confirmar contraseña'), obscureText: true),
                SizedBox(height: 8),
                Row(
                  children: [
                    Text(_birth == null ? 'Fecha de nacimiento' : 'Nacimiento: ${_birth!.toLocal().toIso8601String().split("T")[0]}'),
                    Spacer(),
                    ElevatedButton(onPressed: _pickBirth, child: Text('Elegir')),
                  ],
                ),
              ],
              SizedBox(height: 16),
              _loading ? CircularProgressIndicator() : ElevatedButton(
                onPressed: isRegister ? _register : _login,
                child: Text(isRegister ? 'Registrarme' : 'Iniciar sesión'),
              ),
              SizedBox(height: 8),
              TextButton(onPressed: () => setState(() => isRegister = !isRegister), child: Text(isRegister ? 'Ya tengo cuenta' : 'Crear cuenta')),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------
   MainScreen con BottomNav
   -------------------------- */
class MainScreen extends StatefulWidget {
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int idx = 0;
  final screens = [
    HomeScreen(),
    ForumsScreen(),
    MemesScreen(),
    ChatListScreen(),
    GamesScreen(),
    CallsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[idx],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: idx,
        onTap: (i) => setState(() => idx = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'Foros'),
          BottomNavigationBarItem(icon: Icon(Icons.mood), label: 'Memes'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.sports_esports), label: 'Juegos'),
          BottomNavigationBarItem(icon: Icon(Icons.call), label: 'Llamadas'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }
}

/* --------------------------
   Profile: cambiar foto + figurita (placeholder)
   -------------------------- */
class ProfileScreen extends StatefulWidget {
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends State<ProfileScreen> {
  String? photoUrl;
  String username = '';
  bool loading = false;

  @override
  void initState(){
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = snap.data();
    setState(() {
      photoUrl = data?['photoUrl'];
      username = data?['username'] ?? '';
    });
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final p = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (p == null) return;
    setState(() => loading = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final file = File(p.path);
    final ref = FirebaseStorage.instance.ref().child('profile_photos').child('$uid.jpg');
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'photoUrl': url});
    setState(() {
      photoUrl = url;
      loading = false;
    });
  }

  Future<void> _createFiguritaPlaceholder() async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Figurita: función placeholder (puedo implementar overlay + texto).')));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: Text('Perfil')),
      body: Center(
        child: loading ? CircularProgressIndicator() : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _pickAndUpload,
              child: CircleAvatar(radius: 60, backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null, child: photoUrl==null?Icon(Icons.person,size:60):null),
            ),
            SizedBox(height:8),
            Text(username, style: TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
            SizedBox(height:8),
            ElevatedButton(onPressed: _createFiguritaPlaceholder, child: Text('Crear figurita')),
            SizedBox(height:8),
            ElevatedButton(onPressed: () async {
              await FirebaseAuth.instance.signOut();
            }, child: Text('Cerrar sesión'))
          ],
        ),
      )
    );
  }
}

/* --------------------------
   Home: posts (simplificado)
   -------------------------- */
class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final _postCtrl = TextEditingController();
  final postsRef = FirebaseFirestore.instance.collection('posts');

  Future<void> _createPost() async {
    final t = _postCtrl.text.trim();
    if (t.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await postsRef.add({
      'text': t,
      'author': uid,
      'likes': [],
      'createdAt': FieldValue.serverTimestamp()
    });
    _postCtrl.clear();
  }

  Widget _postTile(DocumentSnapshot doc){
    final d = doc.data() as Map<String,dynamic>;
    final likes = List<String>.from(d['likes'] ?? []);
    return Card(
      margin: EdgeInsets.all(8),
      child: ListTile(
        leading: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(d['author']).get(),
          builder: (context, snap) {
            if (!snap.hasData) return CircleAvatar(child: Icon(Icons.person));
            final u = snap.data!.data() as Map<String,dynamic>?;
            final p = u?['photoUrl'];
            return CircleAvatar(backgroundImage: p != null ? NetworkImage(p) : null, child: p==null?Icon(Icons.person):null);
          },
        ),
        title: Text(d['text'] ?? ''),
        subtitle: Text('Likes: ${likes.length}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: Icon(likes.contains(FirebaseAuth.instance.currentUser!.uid)?Icons.favorite:Icons.favorite_border), onPressed: () async {
            final uid = FirebaseAuth.instance.currentUser!.uid;
            final ref = postsRef.doc(doc.id);
            if (likes.contains(uid)) await ref.update({'likes': FieldValue.arrayRemove([uid])});
            else await ref.update({'likes': FieldValue.arrayUnion([uid])});
          }),
          IconButton(icon: Icon(Icons.comment), onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => CommentsScreen(postId: doc.id)));
          })
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: Column(
        children: [
          Padding(padding: EdgeInsets.all(8), child: Row(children: [
            Expanded(child: TextField(controller: _postCtrl, decoration: InputDecoration(hintText: 'Publicá algo...'))),
            ElevatedButton(onPressed: _createPost, child: Text('Post'))
          ])),
          Expanded(child: StreamBuilder<QuerySnapshot>(
            stream: postsRef.orderBy('createdAt',descending:true).snapshots(),
            builder:(context,snap){
              if(!snap.hasData) return Center(child:CircularProgressIndicator());
              final docs = snap.data!.docs;
              return ListView(children: docs.map((d)=>_postTile(d)).toList());
            }
          ))
        ],
      ),
    );
  }
}

class CommentsScreen extends StatefulWidget {
  final String postId;
  CommentsScreen({required this.postId});
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}
class _CommentsScreenState extends State<CommentsScreen> {
  final _ctrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('posts').doc(widget.postId).collection('comments').orderBy('createdAt');
    return Scaffold(
      appBar: AppBar(title: Text('Comentarios')),
      body: Column(children:[
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: ref.snapshots(),
          builder:(context,snap){
            if(!snap.hasData) return Center(child:CircularProgressIndicator());
            return ListView(children: snap.data!.docs.map((d)=>ListTile(title: Text((d.data() as Map<String,dynamic>)['text'] ?? ''))).toList());
          }
        )),
        Row(children:[
          Expanded(child: TextField(controller: _ctrl, decoration: InputDecoration(hintText: 'Comentá...'))),
          IconButton(icon: Icon(Icons.send), onPressed: () async {
            final t=_ctrl.text.trim();
            if(t.isEmpty) return;
            await FirebaseFirestore.instance.collection('posts').doc(widget.postId).collection('comments').add({
              'text': t,
              'author': FirebaseAuth.instance.currentUser!.uid,
              'createdAt': FieldValue.serverTimestamp()
            });
            _ctrl.clear();
          })
        ])
      ])
    );
  }
}

/* --------------------------
   Foros (simplificado)
   -------------------------- */
class ForumsScreen extends StatelessWidget {
  final _new = TextEditingController();
  final ref = FirebaseFirestore.instance.collection('forums');
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Foros')),
      body: Column(children: [
        Padding(padding: EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: _new, decoration: InputDecoration(hintText: 'Crear foro/deporte...'))),
          ElevatedButton(onPressed: () async {
            final t = _new.text.trim();
            if (t.isEmpty) return;
            await ref.add({'title': t, 'creator': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
            _new.clear();
          }, child: Text('Crear'))
        ])),
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: ref.orderBy('createdAt',descending:true).snapshots(),
          builder:(ctx,snap){
            if(!snap.hasData) return Center(child:CircularProgressIndicator());
            return ListView(children: snap.data!.docs.map((d)=>ListTile(title: Text((d.data() as Map<String,dynamic>)['title'] ?? ''), onTap: (){
              Navigator.push(context, MaterialPageRoute(builder: (_) => SingleForumScreen(forumId: d.id)));
            })).toList());
          }
        ))
      ])
    );
  }
}

class SingleForumScreen extends StatelessWidget {
  final String forumId;
  SingleForumScreen({required this.forumId});
  final _post = TextEditingController();

  @override
  Widget build(BuildContext context){
    final postsRef = FirebaseFirestore.instance.collection('forums').doc(forumId).collection('posts').orderBy('createdAt',descending:true);
    return Scaffold(
      appBar: AppBar(title: Text('Foro')),
      body: Column(children: [
        Padding(padding: EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: _post, decoration: InputDecoration(hintText: 'Escribir en foro...'))),
          ElevatedButton(onPressed: () async {
            final t=_post.text.trim();
            if (t.isEmpty) return;
            await FirebaseFirestore.instance.collection('forums').doc(forumId).collection('posts').add({
              'text': t,
              'author': FirebaseAuth.instance.currentUser!.uid,
              'likes': [],
              'createdAt': FieldValue.serverTimestamp()
            });
            _post.clear();
          }, child: Text('Post'))
        ])),
        Expanded(child: StreamBuilder<QuerySnapshot>(stream: postsRef.snapshots(), builder:(ctx,snap){
          if(!snap.hasData) return Center(child:CircularProgressIndicator());
          return ListView(children: snap.data!.docs.map((d)=>ListTile(title: Text((d.data() as Map<String,dynamic>)['text'] ?? ''))).toList());
        }))
      ]),
    );
  }
}

/* --------------------------
   Memes (simplificado)
   -------------------------- */
class MemesScreen extends StatelessWidget {
  final _ctrl = TextEditingController();
  final ref = FirebaseFirestore.instance.collection('memes');
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Memes')),
      body: Column(children: [
        Padding(padding: EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: _ctrl, decoration: InputDecoration(hintText: 'Compartir meme (texto)...'))),
          ElevatedButton(onPressed: () async {
            final t = _ctrl.text.trim();
            if (t.isEmpty) return;
            await ref.add({'text': t, 'author': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp(), 'likes': []});
            _ctrl.clear();
          }, child: Text('Post'))
        ])),
        Expanded(child: StreamBuilder<QuerySnapshot>(stream: ref.orderBy('createdAt',descending:true).snapshots(), builder:(ctx,snap){
          if(!snap.hasData) return Center(child:CircularProgressIndicator());
          return ListView(children: snap.data!.docs.map((d)=>ListTile(title: Text((d.data() as Map<String,dynamic>)['text'] ?? ''))).toList());
        }))
      ]),
    );
  }
}

/* --------------------------
   Chat list + chat screen (real time)
   -------------------------- */
class ChatListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final q = FirebaseFirestore.instance.collection('chats').where('members', arrayContains: uid).orderBy('createdAt', descending: true);
    return Scaffold(
      appBar: AppBar(title: Text('Chats')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ctrl = TextEditingController();
          showDialog(context: context, builder: (ctx) => AlertDialog(
            title: Text('Crear chat'),
            content: TextField(controller: ctrl, decoration: InputDecoration(hintText: 'UID del otro usuario')),
            actions: [
              TextButton(onPressed: ()=>Navigator.pop(ctx), child: Text('Cancelar')),
              ElevatedButton(onPressed: () async {
                final other = ctrl.text.trim();
                if (other.isEmpty) return;
                final chatId = Uuid().v4();
                await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
                  'members': [uid, other],
                  'createdAt': FieldValue.serverTimestamp()
                });
                Navigator.pop(ctx);
              }, child: Text('Crear'))
            ],
          ));
        },
        child: Icon(Icons.add),
      ),
      body: StreamBuilder<QuerySnapshot>(stream: q.snapshots(), builder:(ctx,snap){
        if(!snap.hasData) return Center(child:CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView(children: docs.map((d){
          final members = List<String>.from(d['members']);
          final other = members.firstWhere((m) => m != uid, orElse: () => members.first);
          return FutureBuilder<DocumentSnapshot>(future: FirebaseFirestore.instance.collection('users').doc(other).get(), builder:(c,snapUser){
            final name = snapUser.data?.get('username') ?? other;
            return ListTile(title: Text(name), subtitle: Text('Chat'), onTap: (){
              Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: d.id)));
            });
          });
        }).toList());
      })
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  ChatScreen({required this.chatId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final messagesRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('createdAt');
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(stream: messagesRef.snapshots(), builder:(ctx,snap){
          if(!snap.hasData) return Center(child:CircularProgressIndicator());
          final docs = snap.data!.docs;
          return ListView(children: docs.map((d) {
            final m = d.data() as Map<String,dynamic>;
            final isMe = m['sender'] == FirebaseAuth.instance.currentUser!.uid;
            return Align(alignment: isMe?Alignment.centerRight:Alignment.centerLeft, child: Container(
              margin: EdgeInsets.symmetric(vertical:4,horizontal:8),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(color:isMe?Colors.blue[200]:Colors.grey[300], borderRadius: BorderRadius.circular(8)),
              child: Text(m['text'] ?? '')
            ));
          }).toList());
        })),
        Row(children: [
          Expanded(child: TextField(controller: _ctrl, decoration: InputDecoration(hintText: 'Escribí...'))),
          IconButton(icon: Icon(Icons.send), onPressed: () async {
            final t=_ctrl.text.trim();
            if (t.isEmpty) return;
            await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
              'text': t,
              'sender': FirebaseAuth.instance.currentUser!.uid,
              'createdAt': FieldValue.serverTimestamp()
            });
            _ctrl.clear();
          })
        ])
      ]),
    );
  }
}

/* --------------------------
   Games Screen (Flame placeholders)
   -------------------------- */
class GamesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Juegos')),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[
          ElevatedButton.icon(onPressed: (){
            Navigator.push(context, MaterialPageRoute(builder: (_) => BasketGameScreen()));
          }, icon: Icon(Icons.sports_basketball), label: Text('Basket - práctica')),
          SizedBox(height:12),
          ElevatedButton.icon(onPressed: (){
            Navigator.push(context, MaterialPageRoute(builder: (_) => MiniHaxballScreen()));
          }, icon: Icon(Icons.sports_soccer), label: Text('Mini Haxball - práctica')),
          SizedBox(height:20),
          Text('Modo multijugador puede implementarse con Firestore/Realtime DB para señalizar partidas')
        ]),
      ),
    );
  }
}

class BasketGameScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context){
    final game = SimpleBasketGame();
    return Scaffold(
      appBar: AppBar(title: Text('Basket (práctica)')),
      body: GameWidget(game: game),
    );
  }
}

// Simple Flame game placeholder
class SimpleBasketGame extends FlameGame {
  int score = 0;
  @override
  Future<void> onLoad() async {
    camera.viewport = FixedResolutionViewport(Vector2(360,640));
  }
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paintRect = Paint()..color = const Color(0xFF1976D2);
    canvas.drawRect(Rect.fromLTWH(0,0, size.x, size.y), paintRect);
    // Placeholder: aquí agregás sprites y lógica de lanzamiento.
  }
}

class MiniHaxballScreen extends StatefulWidget {
  @override
  State<MiniHaxballScreen> createState() => _MiniHaxballScreenState();
}
class _MiniHaxballScreenState extends State<MiniHaxballScreen> {
  double ballX = 150, ballY = 200;
  double vx = 2, vy = 2;

  void tick() {
    setState(() {
      ballX += vx;
      ballY += vy;
      if (ballX < 10 || ballX > 300) vx = -vx;
      if (ballY < 10 || ballY > 500) vy = -vy;
    });
  }

  @override
  void initState(){
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(Duration(milliseconds: 16));
      if (!mounted) return false;
      tick();
      return true;
    });
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Mini Haxball (práctica)')),
      body: Center(child: Container(width:320, height:520, color: Colors.green[200], child: Stack(children: [
        Positioned(left: ballX, top: ballY, child: Icon(Icons.sports_soccer, size: 32))
      ]))),
    );
  }
}

/* --------------------------
   Calls: WebRTC + Firestore signaling (basic)
   -------------------------- */
class CallsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Llamadas')),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        ElevatedButton(onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => CreateCallScreen()));
        }, child: Text('Iniciar llamada (crear)')),
        SizedBox(height:12),
        ElevatedButton(onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => JoinCallScreen()));
        }, child: Text('Unirse a llamada (pegar ID)')),
      ])),
    );
  }
}

// Crear llamada — crea documento en 'calls' y obtiene callId
class CreateCallScreen extends StatefulWidget {
  @override
  State<CreateCallScreen> createState() => _CreateCallScreenState();
}
class _CreateCallScreenState extends State<CreateCallScreen> {
  String? callId;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _pc?.close();
    _localStream?.dispose();
    super.dispose();
  }

  Future<void> _startLocalStream() async {
    final stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
    _localRenderer.srcObject = stream;
    _localStream = stream;
  }

  Future<void> _createCall() async {
    final calls = FirebaseFirestore.instance.collection('calls');
    final doc = calls.doc();
    setState(() => callId = doc.id);
    await doc.set({'createdAt': FieldValue.serverTimestamp()});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call ID: ${doc.id} (usa Unirse para conectar, demo handshake)')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Crear llamada')),
      body: Column(children: [
        Expanded(child: RTCVideoView(_localRenderer, mirror: true)),
        Row(children: [
          ElevatedButton(onPressed: _startLocalStream, child: Text('Activar cámara')),
          SizedBox(width:8),
          ElevatedButton(onPressed: _createCall, child: Text('Crear llamada')),
        ])
      ]),
    );
  }
}

class JoinCallScreen extends StatefulWidget {
  @override
  State<JoinCallScreen> createState() => _JoinCallScreenState();
}
class _JoinCallScreenState extends State<JoinCallScreen> {
  final _ctrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Unirse a llamada')),
      body: Column(children: [
        Padding(padding: EdgeInsets.all(8), child: TextField(controller: _ctrl, decoration: InputDecoration(hintText: 'Pegar Call ID'))),
        ElevatedButton(onPressed: () {
          final id=_ctrl.text.trim();
          if (id.isEmpty) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Función demo: en producción se conecta con WebRTC usando signaling en Firestore. Call ID: $id')));
        }, child: Text('Unirse (demo)'))
      ]),
    );
  }
}

/* --------------------------
   FIN
   -------------------------- */
