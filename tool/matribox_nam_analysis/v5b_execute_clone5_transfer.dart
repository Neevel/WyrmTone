/// V5B entry-point SCAFFOLD ONLY -- HISTORICAL, SUPERSEDED.
///
/// This file exists so a human (not this agent) had a single, narrow,
/// clearly-labelled place to run the real Clone-5 transfer from, at the
/// time V5B was approved. At that time it deliberately could not perform
/// one: no transport talking to a real device existed anywhere in this
/// repository, and building one was explicitly out of scope for V5A/V5B
/// (see docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md, V5B).
///
/// That is no longer the case: a real, hardware-validated Android send
/// transport now exists (`MatriboxNamCloneSendPort`/
/// `MatriboxNamTransferSession`, reached from the Flutter app through the
/// platform-channel service in `lib/services/`), and has completed two
/// real Clone-5 transfers. This `dart run`-from-Windows scaffold was never
/// updated to use it -- it still prints its banner, requires the
/// confirmation phrase, then stops with a clear error instead of opening
/// any connection, exactly as before. No target-slot input, no NAM
/// selection, no raw SysEx path exist here -- both are hardcoded to
/// Clone 5 / JVM410H via [V5TransferPlan] and `v5_clodata_builder.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'nam_golden_corpus.dart';
import 'v5_ack_state_machine.dart';
import 'v5_clodata_builder.dart';
import 'v5_transfer_plan.dart';

const _confirmationPhrase = 'SEND JVM410H TO CLONE 5';

Future<void> main() async {
  stdout.writeln('================================================');
  stdout.writeln('EXPERIMENTAL MATRIBOX NAM TRANSFER');
  stdout.writeln('MODEL: JVM410H STANDARD');
  stdout.writeln('TARGET: CLONE 5');
  stdout.writeln('ONE TRANSFER ATTEMPT ONLY');
  stdout.writeln('NO STORE');
  stdout.writeln('================================================');
  stdout.writeln(
    'This is a research-only, experimental transfer. It is NOT '
    'production-ready. Clone 5 must be a slot whose current content you '
    'do not need to keep.',
  );
  stdout.writeln();
  stdout.writeln('Type exactly "$_confirmationPhrase" to proceed, anything else to abort:');
  final line = stdin.readLineSync();
  if (line != _confirmationPhrase) {
    stdout.writeln('Aborted: confirmation phrase did not match. Nothing was sent.');
    exit(1);
  }

  // Rebuild and re-verify the plan fresh, right before the (not yet
  // implemented) connection step -- never trust a plan built earlier in a
  // different process.
  final golden = matriboxGoldenCorpus.firstWhere((e) => e.id == 'jvm410h-standard');
  final identity = buildV5CloData(namPath: golden.namLocalPath!, cloneName: golden.storedName);
  final plan = V5TransferPlan.build(
    cloData: identity.cloData,
    modelLabel: 'JVM410H Standard',
    cloDataSha256Hex: identity.cloDataSha256Hex,
  );
  stdout.writeln('Pre-execution verification: OK (${plan.frameCount} frames planned).');
  stdout.writeln(jsonEncode(v5IdentitySummary(identity)));

  final budget = V5WriteBudget();
  budget.consumeAttempt(); // The one allowed attempt is spent right here,
  // whether or not a connection ever opens -- matches V5A's "no retry"
  // write-budget rule even for this scaffold.

  stderr.writeln(
    'STOP: no real V5Transport implementation exists in this repository. '
    'Opening a device connection and sending frames from here would '
    'require a separately built, separately tested, separately approved '
    'hardware transport -- not something this scaffold does on its own.',
  );
  exit(2);
}
