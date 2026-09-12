import 'dart:async';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

final class DiscoveredServer { const DiscoveredServer(this.name, this.host); final String name; final String host; }
abstract final class ServerDiscovery {
  static const _channel = MethodChannel('pulgapp/multicast');
  static Future<List<DiscoveredServer>> find() async {
    final client = MDnsClient(); final found = <String, DiscoveredServer>{};
    await _channel.invokeMethod<void>('acquire');
    try {
      await client.start();
      await for (final ptr in client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer('_pulgapp._tcp.local')).timeout(const Duration(seconds: 3))) {
        await for (final srv in client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))) {
            found[ip.address.address] = DiscoveredServer(ptr.domainName, ip.address.address);
            break;
          }
          break;
        }
      }
    } on TimeoutException { } finally { client.stop(); await _channel.invokeMethod<void>('release'); }
    return found.values.toList();
  }
}
