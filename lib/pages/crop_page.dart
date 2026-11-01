import 'package:flutter/material.dart';

import '../state/photo_booth_config.dart';

class CropPage extends StatelessWidget {
  const CropPage({
    super.key,
    required this.config,
  });

  final PhotoBoothConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crop')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Preview transform', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  Text('Scale ${config.cropScale.toStringAsFixed(2)}x'),
                  Slider(
                    value: config.cropScale,
                    min: 0.8,
                    max: 1.6,
                    onChanged: config.setCropScale,
                  ),
                  const SizedBox(height: 12),
                  Text('Horizontal offset ${config.cropOffsetX.toStringAsFixed(2)}'),
                  Slider(
                    value: config.cropOffsetX,
                    min: -0.5,
                    max: 0.5,
                    onChanged: config.setCropOffsetX,
                  ),
                  const SizedBox(height: 12),
                  Text('Vertical offset ${config.cropOffsetY.toStringAsFixed(2)}'),
                  Slider(
                    value: config.cropOffsetY,
                    min: -0.5,
                    max: 0.5,
                    onChanged: config.setCropOffsetY,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () {
              config
                ..setCropScale(1)
                ..setCropOffsetX(0)
                ..setCropOffsetY(0);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset crop tuning'),
          ),
        ],
      ),
    );
  }
}
