// ignore_for_file: unused_field

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:permission_handler/permission_handler.dart'; // Added for permission handling

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skincare Doctor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        primaryColor: Color(0xFF3D8361), // Medical green theme
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: Color(0xFFD6CDA4),
          primary: Color(0xFF3D8361),
        ),
      ),
      home: const SkincareDoctorChat(),
    );
  }
}

class SkincareDoctorChat extends StatefulWidget {
  const SkincareDoctorChat({super.key});

  @override
  State<SkincareDoctorChat> createState() => _SkincareDoctorChatState();
}

class _SkincareDoctorChatState extends State<SkincareDoctorChat> {
  XFile? pickedImage;
  String doctorResponse = '';
  bool scanning = false;
  bool isTTS = true; // Set default to true for better experience

  // Language selection
  String selectedLanguage = 'en-US'; // Default language
  String selectedLanguageName = 'English'; // Display name

  // Map for language codes and display names
  final Map<String, Map<String, String>> languageOptions = {
    'English': {'code': 'en-US', 'prompt': 'Describe your skin concern...'},
    'Hindi': {
      'code': 'hi-IN',
      'prompt': 'अपनी त्वचा की समस्या का वर्णन करें...'
    },
    'Marathi': {
      'code': 'mr-IN',
      'prompt': 'तुमच्या त्वचेच्या समस्येचे वर्णन करा...'
    },
  };

  // Speech to text
  SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = '';

  // Text to speech
  FlutterTts flutterTts = FlutterTts();

  TextEditingController prompt = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  // Replace with your API key
  final apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=AIzaSyA-a20TEUI-x6x6z1P2E9EdVErduW77P1E';

  final header = {
    'Content-Type': 'application/json',
  };

  // The predefined skincare doctor prompt with language instruction
  String get skincareDoctorPrompt {
    String languageInstruction = '';

    if (selectedLanguageName == 'Hindi') {
      languageInstruction = 'Please respond in Hindi language only. ';
    } else if (selectedLanguageName == 'Marathi') {
      languageInstruction = 'Please respond in Marathi language only. ';
    }

    return """${languageInstruction}You have to act as a professional doctor, i know you are not but this is for learning purpose. What's in this image?. Do you find anything wrong with it medically? If you make a differential, suggest some remedies for them. Do not add any numbers or special characters in your response. Your response should be in one long paragraph. Also always answer as if you are answering to a real person. Donot say 'In the image I see' but say 'With what I see, I think you have ....' Dont respond as an AI model in markdown, your answer should mimic that of an actual doctor not an AI bot, Keep your answer concise (max 2 sentences). No preamble, start your answer right away please""";
  }

  @override
  void initState() {
    super.initState();
    _requestPermissions(); // Added permission request at startup
    _initSpeech();
    _initTTS();

    // Set a default user query that can be modified
    prompt.text = "Can you examine my skin condition?";
  }

  // Request permissions needed for the app
  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.storage.request();
  }

  // Initialize speech recognition
  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize();
      setState(() {});
    } catch (e) {
      print('Error initializing speech: $e');
      _speechEnabled = false;
      setState(() {});
    }
  }

  // Initialize text to speech
  void _initTTS() async {
    try {
      await flutterTts.setLanguage(selectedLanguage);
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);
    } catch (e) {
      print('Error initializing TTS: $e');
    }
  }

  // Change language settings
  void _changeLanguage(String languageName) async {
    if (languageOptions.containsKey(languageName)) {
      setState(() {
        selectedLanguageName = languageName;
        selectedLanguage = languageOptions[languageName]!['code']!;

        // Update placeholder text based on selected language
        if (prompt.text.isEmpty ||
            prompt.text == "Can you examine my skin condition?" ||
            prompt.text ==
                "क्या आप मेरी त्वचा की स्थिति की जांच कर सकते हैं?" ||
            prompt.text == "तुम्ही माझ्या त्वचेची स्थिती तपासू शकता का?") {
          if (languageName == 'English') {
            prompt.text = "Can you examine my skin condition?";
          } else if (languageName == 'Hindi') {
            prompt.text = "क्या आप मेरी त्वचा की स्थिति की जांच कर सकते हैं?";
          } else if (languageName == 'Marathi') {
            prompt.text = "तुम्ही माझ्या त्वचेची स्थिती तपासू शकता का?";
          }
        }
      });

      // Update TTS language
      try {
        await flutterTts.setLanguage(selectedLanguage);
      } catch (e) {
        print('Error setting TTS language: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Language changed to $languageName'),
          duration: const Duration(seconds: 1),
          backgroundColor: Theme.of(context).primaryColor,
        ),
      );
    }
  }

  // Start listening for speech
  void _startListening() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }

    // Set the speech recognition language
    try {
      await _speechToText.listen(
        onResult: _onSpeechResult,
        localeId: selectedLanguage,
      );
      setState(() {});
    } catch (e) {
      print('Error starting speech recognition: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Could not access microphone. Please check app permissions.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Stop listening for speech
  void _stopListening() async {
    try {
      await _speechToText.stop();
      setState(() {});
    } catch (e) {
      print('Error stopping speech recognition: $e');
    }
  }

  // Process speech recognition result
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      prompt.text = _lastWords;

      // If this is the final result, process the input
      if (result.finalResult) {
        _stopListening();
      }
    });
  }

  // Toggle text-to-speech feature
  void _toggleTTS() {
    setState(() {
      isTTS = !isTTS;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isTTS ? 'Doctor voice enabled' : 'Doctor voice disabled'),
        duration: const Duration(seconds: 1),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  // Show language selection menu
  void _showLanguageMenu() {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(100, 80, 0, 0),
      items: languageOptions.keys.map((String language) {
        return PopupMenuItem<String>(
          value: language,
          child: Row(
            children: [
              Text(language),
              SizedBox(width: 8),
              if (selectedLanguageName == language)
                Icon(Icons.check, color: Theme.of(context).primaryColor),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        _changeLanguage(value);
      }
    });
  }

  // Speak the response text
  void _speakResponse(String text) async {
    if (isTTS) {
      try {
        await flutterTts.speak(text);
      } catch (e) {
        print('Error speaking text: $e');
      }
    }
  }

  // Show image source selection dialog
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Take or Select a Skin Photo',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildImageSourceOption(
                      icon: Icons.photo_library,
                      title: 'Gallery',
                      onTap: () {
                        Navigator.of(context).pop();
                        getImage(ImageSource.gallery);
                      },
                    ),
                    _buildImageSourceOption(
                      icon: Icons.camera_alt,
                      title: 'Camera',
                      onTap: () {
                        Navigator.of(context).pop();
                        getImage(ImageSource.camera);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Build image source option
  Widget _buildImageSourceOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 30,
            ),
          ),
          SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  // Get image from gallery or camera
 getImage(ImageSource ourSource) async {
    try {
      // Check permission first
      if (ourSource == ImageSource.camera) {
        var status = await Permission.camera.status;
        if (!status.isGranted) {
          await Permission.camera.request();
          status = await Permission.camera.status;
          if (!status.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Camera permission is required'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }
      } else {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          await Permission.storage.request();
          status = await Permission.storage.status;
          if (!status.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Storage permission is required'),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }
      }

      XFile? result = await _imagePicker.pickImage(
        source: ourSource,
        imageQuality: 80, // Optimize for faster uploads
      );

      if (result != null) {
        setState(() {
          pickedImage = result;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Could not access ${ourSource == ImageSource.camera ? 'camera' : 'gallery'}. Please check app permissions.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Get default prompt based on selected language
  String getDefaultPrompt() {
    switch (selectedLanguageName) {
      case 'Hindi':
        return "क्या आप मेरी त्वचा की स्थिति की जांच कर सकते हैं?";
      case 'Marathi':
        return "तुम्ही माझ्या त्वचेची स्थिती तपासू शकता का?";
      default:
        return "Can you examine my skin condition?";
    }
  }

  // Process the image and prompt with Gemini API
  getdata(image, userPrompt) async {
    setState(() {
      scanning = true;
      doctorResponse = '';
    });

    try {
      List<int> imageBytes = File(image.path).readAsBytesSync();
      String base64File = base64.encode(imageBytes);

      // Combine user prompt with the skincare doctor prompt
      String combinedPrompt =
          "$skincareDoctorPrompt\n\nPatient says: $userPrompt";

      final data = {
        "contents": [
          {
            "parts": [
              {"text": combinedPrompt},
              {
                "inlineData": {
                  "mimeType": "image/jpeg",
                  "data": base64File,
                }
              }
            ]
          }
        ],
      };

      await http
          .post(Uri.parse(apiUrl), headers: header, body: jsonEncode(data))
          .then((response) {
        if (response.statusCode == 200) {
          var result = jsonDecode(response.body);
          doctorResponse =
              result['candidates'][0]['content']['parts'][0]['text'];

          // Speak the response if TTS is enabled
          _speakResponse(doctorResponse);
        } else {
          // Error responses in selected language
          if (selectedLanguageName == 'Hindi') {
            doctorResponse =
                'मुझे क्षमा करें, लेकिन मैं अभी आपकी स्थिति का विश्लेषण करने में असमर्थ हूं। कृपया बाद में पुनः प्रयास करें।';
          } else if (selectedLanguageName == 'Marathi') {
            doctorResponse =
                'मला क्षमा करा, पण मी सध्या तुमच्या स्थितीचे विश्लेषण करू शकत नाही. कृपया नंतर पुन्हा प्रयत्न करा.';
          } else {
            doctorResponse =
                'I apologize, but I am unable to analyze your condition at the moment. Please try again later.';
          }
        }
      }).catchError((error) {
        print('Error occurred: $error');

        // Error responses in selected language
        if (selectedLanguageName == 'Hindi') {
          doctorResponse =
              'मुझे क्षमा करें, लेकिन मैं तकनीकी कठिनाइयों का सामना कर रहा हूं। कृपया बाद में पुनः प्रयास करें।';
        } else if (selectedLanguageName == 'Marathi') {
          doctorResponse =
              'मला क्षमा करा, पण मला तांत्रिक अडचणींचा सामना करावा लागत आहे. कृपया नंतर पुन्हा प्रयत्न करा.';
        } else {
          doctorResponse =
              'I apologize, but I am experiencing technical difficulties. Please try again later.';
        }
      });
    } catch (e) {
      print('Error occurred: $e');

      // Error responses in selected language
      if (selectedLanguageName == 'Hindi') {
        doctorResponse =
            'मुझे क्षमा करें, लेकिन आपकी छवि को संसाधित करने में त्रुटि हुई थी। कृपया पुनः प्रयास करें।';
      } else if (selectedLanguageName == 'Marathi') {
        doctorResponse =
            'मला क्षमा करा, पण तुमची प्रतिमा प्रक्रिया करताना त्रुटी झाली. कृपया पुन्हा प्रयत्न करा.';
      } else {
        doctorResponse =
            'I apologize, but there was an error processing your image. Please try again.';
      }
    }

    setState(() {
      scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.medical_services, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'Skincare Doctor',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          // Language selection button
          IconButton(
            onPressed: _showLanguageMenu,
            icon: Row(
              children: [
                Icon(
                  Icons.translate,
                  color: Colors.white,
                ),
                SizedBox(width: 4),
                Text(
                  selectedLanguageName.substring(
                      0, 2), // Display first 2 letters of language
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            tooltip: 'Change language',
          ),
          // Toggle TTS button
          IconButton(
            onPressed: _toggleTTS,
            icon: Icon(
              isTTS ? Icons.volume_up : Icons.volume_off,
              color: Colors.white,
            ),
            tooltip: 'Toggle doctor voice',
          ),
          SizedBox(width: 10),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            // Image display area - now clickable
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 340,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                    color: Theme.of(context).primaryColor,
                    width: 2.0,
                  ),
                ),
                child: pickedImage == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo,
                            size: 60,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Take or Upload Skin Photo',
                            style: TextStyle(fontSize: 22),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'For accurate diagnosis',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      )
                    : Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.file(
                              File(pickedImage!.path),
                              width: double.infinity,
                              height: 340,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .primaryColor
                                    .withOpacity(0.8),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                ),
                                onPressed: _showImageSourceDialog,
                                tooltip: 'Change image',
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            SizedBox(height: 20),

            // Prompt input with voice button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: prompt,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 2.0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 2.0,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.question_answer,
                        color: Theme.of(context).primaryColor,
                      ),
                      hintText:
                          languageOptions[selectedLanguageName]!['prompt'],
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () =>
                      _startListening(), // Modified to always be active
                  child: Icon(
                    Icons.mic,
                    color: Colors.white,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(15),
                  ),
                ),
              ],
            ),

            SizedBox(height: 20),

            // Consult button
            ElevatedButton.icon(
              onPressed: () {
                if (pickedImage != null) {
                  // If prompt is empty, use a default prompt based on language
                  String userQuery =
                      prompt.text.isEmpty ? getDefaultPrompt() : prompt.text;
                  getdata(pickedImage, userQuery);
                } else {
                  String errorMessage =
                      'Please take or upload a skin photo first';

                  // Error message in selected language
                  if (selectedLanguageName == 'Hindi') {
                    errorMessage = 'कृपया पहले त्वचा की फोटो लें या अपलोड करें';
                  } else if (selectedLanguageName == 'Marathi') {
                    errorMessage =
                        'कृपया प्रथम त्वचेचा फोटो घ्या किंवा अपलोड करा';
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red.shade700,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: Icon(Icons.health_and_safety, color: Colors.white),
              label: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Consult Doctor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            SizedBox(height: 30),

            // Doctor Response Section
            scanning
                ? Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Center(
                      child: Column(
                        children: [
                          SpinKitPulse(
                            color: Theme.of(context).primaryColor,
                            size: 50,
                          ),
                          SizedBox(height: 20),
                          Text(
                            selectedLanguageName == 'Hindi'
                                ? "डॉक्टर आपकी त्वचा का विश्लेषण कर रहे हैं..."
                                : selectedLanguageName == 'Marathi'
                                    ? "डॉक्टर तुमच्या त्वचेचे विश्लेषण करत आहेत..."
                                    : "Doctor is analyzing your skin...",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Card(
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Container(
                      constraints: BoxConstraints(
                        minHeight: 150,
                        maxHeight: 400,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            Color(0xFFF5F5F5),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  color: Theme.of(context).primaryColor,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  selectedLanguageName == 'Hindi'
                                      ? 'डॉक्टर का मूल्यांकन'
                                      : selectedLanguageName == 'Marathi'
                                          ? 'डॉक्टरचे मूल्यांकन'
                                          : 'Doctor\'s Assessment',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                                Spacer(),
                                if (doctorResponse.isNotEmpty)
                                  IconButton(
                                    icon: Icon(
                                      Icons.volume_up,
                                      color: Theme.of(context)
                                          .primaryColor
                                          .withOpacity(0.8),
                                    ),
                                    onPressed: () =>
                                        _speakResponse(doctorResponse),
                                    tooltip: 'Listen to doctor',
                                  ),
                              ],
                            ),
                          ),
                          Divider(thickness: 1, height: 1),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(16),
                              child: SelectableText(
                                doctorResponse.isEmpty
                                    ? selectedLanguageName == 'Hindi'
                                        ? 'डॉक्टर के मूल्यांकन के लिए अपनी त्वचा की समस्या की एक फोटो अपलोड करें। आपका परामर्श यहां दिखाई देगा।'
                                        : selectedLanguageName == 'Marathi'
                                            ? 'डॉक्टरांनी मूल्यांकन करण्यासाठी तुमच्या त्वचेच्या समस्येचा फोटो अपलोड करा. तुमचा सल्लामसलत येथे दिसेल.'
                                            : 'Upload a photo of your skin concern for the doctor to assess. Your consultation will appear here.'
                                    : doctorResponse,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: doctorResponse.isEmpty
                                      ? Colors.grey.shade600
                                      : Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
