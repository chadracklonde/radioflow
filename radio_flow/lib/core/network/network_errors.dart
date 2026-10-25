import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Vrai si l'erreur vient du réseau (l'opération doit être retentée plus tard).
/// Les erreurs du serveur (droits, contraintes) ne sont pas des erreurs réseau.
bool isNetworkError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is http.ClientException ||
    e is AuthRetryableFetchException;

/// Violation d'unicité : l'élément existe déjà (envoi déjà réussi auparavant).
bool isDuplicate(Object e) => e is PostgrestException && e.code == '23505';
