import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:clipboard/clipboard.dart';

class _FileWrapper {
  final File _file;

  Uint8List _rawDataCache;

  Completer<Uint8List> _rawDataCompleter;

  List<dynamic> _excelDataCache;

  bool _parsing = false;

  _FileWrapper(this._file);

  Future<Uint8List> getRawData() async {
    if (_rawDataCache != null) return _rawDataCache;
    if (_parsing) return _rawDataCompleter.future;
    _rawDataCompleter = Completer<Uint8List>();
    _parsing = true;
    final reader = FileReader();
    final fileName = _file.name;
    reader.onLoadEnd.listen((_) {
      print('$fileName, ${_file.type}, ${_file.size}');
    });
    reader.readAsArrayBuffer(_file);
    await reader.onLoadEnd.first;
    _parsing = false;
    _rawDataCache = reader.result as Uint8List;
    _rawDataCompleter.complete(_rawDataCache);
    return _rawDataCache;
  }

  Future<List<dynamic>> getExcelData() async {
    return _excelDataCache ??= _parseExcelData(await getRawData());
  }

  Future<String> getJson(bool pretty) async {
    return (pretty ? JsonEncoder.withIndent('  ') : JsonEncoder()).convert(await getExcelData());
  }

  List<dynamic> _parseExcelData(Uint8List data) {
    final ret = <dynamic>[];
    if (data == null || data.length == 0) return ret;
    final excel = Excel.decodeBytes(data);
    if (excel.sheets.length == 0) return ret;
    ret.addAll(excel.sheets[excel.sheets.keys.first].rows);
    return ret;
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FileUploadInputElement _uploadHandler;

  Map<String, _FileWrapper> _excelData;

  String _selectedFile;

  bool _prettyJson = false;

  @override
  void initState() {
    _excelData = <String, _FileWrapper>{};
    _uploadHandler = FileUploadInputElement()
      ..multiple = true
      ..onChange.listen(onHandlerChanged);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final contentSize = MediaQuery.of(context).size;
    return Scaffold(
      body: Container(
        width: contentSize.width,
        height: contentSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var name in _excelData.keys)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      child: ActionChip(
                        key: ValueKey(name),
                        label: Text(name),
                        backgroundColor: name == _selectedFile ? Colors.pinkAccent : Colors.grey,
                        onPressed: () {
                          setState(() {
                            _selectedFile = name;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 20),
                padding: const EdgeInsets.all(10),
                constraints: BoxConstraints.expand(),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey, width: 2),
                ),
                child: _excelData.length == 0
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.upload_file,
                            size: 80,
                          ),
                          Text(
                            'Upload Excel File to Parse',
                            style: TextStyle(
                              fontSize: 42,
                              height: 4,
                            ),
                          ),
                        ],
                      )
                    : FutureBuilder<String>(
                        future: _excelData[_selectedFile].getJson(_prettyJson),
                        builder: (c, snapshot) => snapshot.hasData
                            ? SingleChildScrollView(
                                child: Text(
                                  snapshot.data,
                                  style: TextStyle(height: 1.6),
                                ),
                              )
                            : Center(
                                child: CircularProgressIndicator(),
                              ),
                      ),
              ),
            ),
            SizedBox(
              height: 100,
              child: Row(
                children: [
                  if (_selectedFile != null)
                    FlatButton.icon(
                      icon: _prettyJson ? Icon(Icons.check_box) : Icon(Icons.check_box_outline_blank),
                      label: Text('Prettify JSON'),
                      onPressed: () => setState(() => _prettyJson = !_prettyJson),
                    ),
                  Spacer(),
                  RaisedButton(
                    color: Colors.pinkAccent,
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(30),
                    child: Icon(Icons.upload_file),
                    onPressed: _uploadHandler.click,
                  ),
                  if (_selectedFile != null) ...[
                    RaisedButton(
                      color: Colors.pinkAccent,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(30),
                      child: Icon(Icons.file_download),
                      onPressed: _downloadParsedFile,
                    ),
                    Builder(
                      builder: (builderContext) => RaisedButton(
                        color: Colors.pinkAccent,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(30),
                        child: Icon(Icons.file_copy),
                        onPressed: () async {
                          final jsonStr = await _excelData[_selectedFile].getJson(_prettyJson);
                          await FlutterClipboard.copy(jsonStr);
                          Scaffold.of(builderContext).showSnackBar(
                            SnackBar(
                              content: Text('JSON Copied'),
                              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(milliseconds: 1500),
                            ),
                          );
                        },
                      ),
                    ),
                  ]
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _downloadParsedFile() async {
    if (_selectedFile == null || _excelData[_selectedFile] == null) return;
    final json = await _excelData[_selectedFile].getJson(_prettyJson);
    final blob = Blob([json], 'text/plain', 'native');
    final url = Url.createObjectUrlFromBlob(blob);
    AnchorElement(href: url)
      ..setAttribute("download", '${_selectedFile.split('.')[0]}.json')
      ..click();
    Url.revokeObjectUrl(url);
  }

  void onHandlerChanged(Event e) async {
    final files = _uploadHandler.files.where((element) => element.name.contains('xlsx'));
    if (files.isEmpty) return;
    setState(() {
      _excelData
        ..clear()
        ..addEntries(files.map((file) => MapEntry(file.name, _FileWrapper(file))));
      _selectedFile = _excelData.keys.first;
    });
  }
}
