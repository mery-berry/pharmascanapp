import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'mes.dart';

class GpsPage extends StatefulWidget {
  const GpsPage({super.key});

  @override
  State<GpsPage> createState() => _GpsPageState();
}

class _GpsPageState extends State<GpsPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  String _debugInfo = 'Initializing...';
  bool _usingRealData = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      setState(() => _debugInfo = 'Getting your location...');

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _debugInfo = 'Please enable location services');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          setState(() => _debugInfo = 'Location permission required');
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _debugInfo = 'Location found! Loading pharmacies...';
      });

      await _fetchRealPharmacies();
    } catch (e) {
      print('❌ Location error: $e');
      setState(() => _debugInfo = 'Error: $e');
      _createDemoPharmacies();
    }
  }

  Future<void> _fetchRealPharmacies() async {
    if (_currentLocation == null) return;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
        'location=${_currentLocation!.latitude},${_currentLocation!.longitude}'
        '&radius=5000'
        '&type=pharmacy'
        '&key=AIzaSyC5owQZxSaEA80sT7lYTkq9TWKc2pw8qFI',
      );

      print('🌐 Fetching real pharmacies from Google Places API...');
      final response = await http.get(url);
      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('📊 API Status: ${data['status']}');

        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          print('✅ SUCCESS: Found ${results.length} real pharmacies!');
          print('📦 Raw result sample: ${results.isNotEmpty ? results.first : "No results"}');
          _createRealMarkers(results);
          return;
        } else {
          print('❌ API Error: ${data['status']} - ${data['error_message'] ?? 'No error message'}');
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Network error: $e');
    }

    _createDemoPharmacies();
  }

  void _createRealMarkers(List<dynamic> pharmacies) {
  if (pharmacies.isEmpty) {
    _createDemoPharmacies();
    return;
  }

  final Set<Marker> newMarkers = {};

  // User location marker
  newMarkers.add(
    Marker(
      markerId: const MarkerId('current_location'),
      position: _currentLocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      consumeTapEvents: false,
    ),
  );

  int count = 0;
  for (int i = 0; i < pharmacies.length; i++) {
    final pharmacy = pharmacies[i];
    final name = pharmacy['name'] ?? 'Pharmacie ${i + 1}';
    final lat = (pharmacy['geometry']?['location']?['lat'])?.toDouble();
    final lng = (pharmacy['geometry']?['location']?['lng'])?.toDouble();
    if (lat == null || lng == null) continue;

    newMarkers.add(
      Marker(
        markerId: MarkerId('pharmacy_$i'),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        consumeTapEvents: true,
        onTap: () => _onPharmacyTapped(name),
      ),
    );
    count++;
  }

  if (mounted) {
    setState(() {
      _markers.clear();
      _markers.addAll(newMarkers);
      _isLoading = false;
      _usingRealData = true;
      _debugInfo = '✅ $count pharmacies trouvées';
    });
  }

  Future.delayed(const Duration(milliseconds: 500), _zoomToShowAllMarkers);
}

void _createDemoPharmacies() {
  if (_currentLocation == null) return;

  final Set<Marker> newMarkers = {};
  newMarkers.add(
    Marker(
      markerId: const MarkerId('current_location'),
      position: _currentLocation!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
    ),
  );

  const int demoCount = 4;
  const double radius = 0.015;

  for (int i = 0; i < demoCount; i++) {
    final angle = 2 * math.pi * i / demoCount;
    final lat = _currentLocation!.latitude + radius * math.cos(angle);
    final lng = _currentLocation!.longitude + radius * math.sin(angle);
    final name = 'Pharmacie ${['Centrale', 'du Nord', 'du Sud', 'de l\'Ouest'][i]}';

    newMarkers.add(
      Marker(
        markerId: MarkerId('demo_$i'),
        position: LatLng(lat, lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        consumeTapEvents: true,
        onTap: () => _onPharmacyTapped(name),
      ),
    );
  }

  setState(() {
    _markers.clear();
    _markers.addAll(newMarkers);
    _isLoading = false;
    _usingRealData = false;
    _debugInfo = 'Mode démo (API de secours)';
  });

  Future.delayed(const Duration(milliseconds: 500), _zoomToShowAllMarkers);
}

void _onPharmacyTapped(String pharmacyId) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Ordonnance envoyée'),
        content: Text(
          'Votre ordonnance a été envoyée ".\n'
          'Voulez-vous discuter avec cette pharmacie ?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Votre prescription a été envoyée.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Non'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
            ),
            onPressed: () {
              Navigator.pop(context);
              _navigateToMessages("default_pharmacy");
            },
            child: const Text('Oui'),
          ),
        ],
      );
    },
  );
}
void _navigateToMessages(String pharmacyId) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MessagesPage(
        pharmacyId: pharmacyId, // 👈 or pharmacyId depending on your MessagesPage constructor
      ),
    ),
  );
}


  void _zoomToShowAllMarkers() {
    if (_mapController == null || _markers.length < 2) return;

    try {
      final bounds = _calculateBounds();
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } catch (e) {
    }
  }

  LatLngBounds _calculateBounds() {
    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;

    for (final m in _markers) {
      final lat = m.position.latitude;
      final lng = m.position.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    print('🗺️ Map ready');
    if (_markers.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 800), _zoomToShowAllMarkers);
    }
  }

  void _refreshData() {
    setState(() {
      _isLoading = true;
      _markers.clear();
      _debugInfo = 'Refreshing...';
    });
    _initializeLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacies à proximité'),
        backgroundColor: const Color(0xFF00C853),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
        ],
      ),
      body: _isLoading || _currentLocation == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(_debugInfo, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _refreshData,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentLocation!,
                    zoom: 13,
                  ),
                  onMapCreated: _onMapCreated,
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _usingRealData ? Colors.green[800] : Colors.orange[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _debugInfo,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _markers.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF00C853),
              onPressed: _zoomToShowAllMarkers,
              child: const Icon(Icons.zoom_out_map, color: Colors.white),
            )
          : null,
    );
  }
}
