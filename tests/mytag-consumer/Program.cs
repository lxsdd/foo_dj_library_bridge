using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using RekordboxMyTagSync.Core;

// Compile-only settings stub. Only the two original read-only Bridge consumer
// sources are linked; Discover(settings) is not invoked. The production
// BridgeSourceDiscovery.ReadStable/Inspect and BridgeSnapshot are unmodified.
namespace RekordboxMyTagSync.Core
{
    public sealed class AppSettings
    {
        public string? EffectiveBridgeDirectory { get; set; }
        public IReadOnlyList<string> EffectiveKnownBridgeDirectories { get; set; }
            = Array.Empty<string>();
    }
    public static class AppSettingsStore
    {
        public static AppSettings ValidateAndNormalize(AppSettings settings) => settings;
    }
}

internal static class MyTagBridgeInterop
{
    static void Must(bool condition, string message)
    {
        if (!condition) throw new InvalidDataException(message);
    }

    static int Main(string[] args)
    {
        try
        {
            Must(args.Length == 1, "Expected isolated native Publisher fixture root");
            (string name, int generation, int count)[] stages = {
                ("g1-empty", 1, 0),
                ("g2-add", 2, 2),
                ("g3-edit", 3, 2),
                ("g4-remove", 4, 1),
                ("g5-coalesced", 5, 3),
                ("g6-restart", 6, 3),
                ("g7-delete", 7, 0),
                ("g8-many", 8, 1024),
                ("g10-recovery", 10, 1),
                ("g11-large", 11, 54129),
                ("identity-valid-subsongs", 1, 2),
                ("identity-recovered-subsongs", 3, 2)
            };
            string? oldFingerprint = null;
            foreach (var (name, generation, count) in stages)
            {
                var dir = Path.Combine(args[0], "stages", name);
                var candidate = BridgeSourceDiscovery.Inspect(dir, selected: true);
                Must(candidate.Safe && candidate.Selected && candidate.State is not null &&
                     candidate.State.SchemaVersion == 3 &&
                     candidate.State.Generation == generation &&
                     candidate.State.ItemCount == count,
                     "MyTagSync original BridgeSourceDiscovery.Inspect rejected " + name
                     + ": " + candidate.Error);

                var snapshot = BridgeSourceDiscovery.ReadStable(dir);
                Must(snapshot.State.SchemaVersion == 3 &&
                     snapshot.State.Generation == generation &&
                     snapshot.State.SourceId == "ci-synthetic-source" &&
                     snapshot.Tracks.Count == count,
                     "MyTagSync ReadStable returned wrong generation/count " + name);

                var identities = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var track in snapshot.Tracks)
                {
                    Must(identities.Add(track.Path + "\n" +
                         track.Subsong.ToString(CultureInfo.InvariantCulture)),
                         "MyTagSync consumer accepted duplicate physical identity");
                    Must(track.GetFieldValues("ARTIST").SequenceEqual(new[] {"Synthetic Artist"}) &&
                         track.GetFieldValues("GENRE").SequenceEqual(new[] {"Trance"}) &&
                         track.GetFieldValues("MOOD").SequenceEqual(new[] {"Synthetic", "CI"}) &&
                         track.GetFieldValues("codec").SequenceEqual(new[] {"FLAC"}) &&
                         track.GetFieldValues("duration_seconds").SequenceEqual(new[] {"240.5"}),
                         "MyTagSync original producer-field mapping drifted: " + name);
                }
                if (name == "g2-add")
                    oldFingerprint = snapshot.Tracks.Single(x =>
                        x.GetFieldValues("TITLE").SequenceEqual(new[] {"Alpha"})).GetFieldValues("TITLE")[0];
                if (name == "g3-edit")
                    Must(snapshot.Tracks.Any(x =>
                        x.GetFieldValues("TITLE").SequenceEqual(new[] {"Alpha (updated)"})) &&
                         oldFingerprint == "Alpha",
                         "MyTagSync consumer lost updated title vector");
                if (name == "g4-remove")
                    Must(snapshot.Tracks.Single().GetFieldValues("TITLE")
                         .SequenceEqual(new[] {"Alpha (updated)"}),
                         "MyTagSync consumer retained removed row");
                if (name == "g5-coalesced")
                    Must(snapshot.Tracks.Any(x =>
                         x.GetFieldValues("TITLE").SequenceEqual(new[] {"Burst final"})),
                         "MyTagSync consumer lost last coalesced event");
                if (name == "g10-recovery")
                    Must(snapshot.Tracks.Single().GetFieldValues("TITLE")
                         .SequenceEqual(new[] {"Recovered after failure"}),
                         "MyTagSync reader lost successful recovery");
                if (name.StartsWith("identity-", StringComparison.Ordinal))
                {
                    Must(snapshot.Tracks.Count == 2 &&
                         snapshot.Tracks[0].Path.Equals(snapshot.Tracks[1].Path, StringComparison.OrdinalIgnoreCase) &&
                         snapshot.Tracks.Select(x => x.Subsong).OrderBy(x => x).SequenceEqual(new[] {0, 1}) &&
                         snapshot.Tracks.Single(x => x.Subsong == 0).GetFieldValues("TITLE").SequenceEqual(new[] {"CUE subsong A"}) &&
                         snapshot.Tracks.Single(x => x.Subsong == 1).GetFieldValues("TITLE").SequenceEqual(new[] {"CUE subsong B"}),
                         "Original MyTagSync reader lost CUE subsong identities or lossless title vectors: " + name);
                    Console.WriteLine("NATIVE_ORIGINAL_MYTAG_CUE_SUBSONGS=PASS " + name);
                }
                if (name == "g11-large")
                    Must(snapshot.Tracks[0].GetFieldValues("TITLE").Single().StartsWith(
                         "Synthetic library track ", StringComparison.Ordinal),
                         "MyTagSync 54k full native output not projected");
                Console.WriteLine("NATIVE_BRIDGE_TO_ORIGINAL_MYTAG_STAGE_" +
                                  generation + "=PASS count=" + count);
            }

            var incomplete = Path.Combine(args[0], "stages", "g9-fail-closed");
            var rejected = BridgeSourceDiscovery.Inspect(incomplete, selected: true);
            Must(!rejected.Safe, "MyTagSync Inspect accepted an incomplete atomic marker");
            bool readRejected = false;
            try { _ = BridgeSourceDiscovery.ReadStable(incomplete); }
            catch (InvalidDataException) { readRejected = true; }
            Must(readRejected, "MyTagSync ReadStable accepted an incomplete atomic marker");
            Console.WriteLine("NATIVE_BRIDGE_MYTAG_INCOMPLETE_REJECTED=PASS");
            Console.WriteLine("NATIVE_BRIDGE_TO_ORIGINAL_MYTAG_SYNC=PASS");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("NATIVE_BRIDGE_TO_ORIGINAL_MYTAG_SYNC=FAIL " + ex);
            return 1;
        }
    }
}
