using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace DJLibrary
{
    // Build-only carrier matching the exact property contract of the original
    // SHA-pinned DJ Library BridgeSnapshot.cs. No application source is modified.
    public sealed class DigitalItem
    {
        public int ItemId { get; set; }
        public string Path { get; set; } = "";
        public int Subsong { get; set; }
        public string Artist { get; set; } = "";
        public string Title { get; set; } = "";
        public string OriginalTitle { get; set; } = "";
        public string RemixedBy { get; set; } = "";
        public string Album { get; set; } = "";
        public string AlbumArtist { get; set; } = "";
        public string Genre { get; set; } = "";
        public string Style { get; set; } = "";
        public double Bpm { get; set; }
        public string Label { get; set; } = "";
        public string Catalog { get; set; } = "";
        public double DurationSeconds { get; set; }
        public string Codec { get; set; } = "";
        public string Bitrate { get; set; } = "";
        public string Fingerprint { get; set; } = "";
        public string MetadataVectorsJson { get; set; } = "";
    }
}

internal static class BridgeNativeWindowsConsumer
{
    static void Must(bool condition, string message)
    {
        if (!condition) throw new InvalidDataException(message);
    }
    static int Main(string[] args)
    {
        try
        {
            Must(args.Length == 1, "Expected disposable publisher fixture root");
            var stages = new (string Name, int Generation, int Count)[] {
                ("g1-empty", 1, 0),
                ("g2-add", 2, 2),
                ("g3-edit", 3, 2),
                ("g4-remove", 4, 1),
                ("g5-coalesced", 5, 3),
                ("g6-restart", 6, 3),
                ("g7-delete", 7, 0),
                ("g8-many", 8, 1024)
            };
            string oldFingerprint = "";
            foreach (var stage in stages)
            {
                string directory = System.IO.Path.Combine(args[0], "stages", stage.Name);
                DJLibrary.BridgeSnapshotStatus status =
                    DJLibrary.BridgeSnapshotReader.Inspect(directory, true);
                Must(status.Present && status.Compatible && status.Complete &&
                     status.Error == null && status.SchemaVersion == 3 &&
                     status.Generation == stage.Generation &&
                     status.DeclaredItemCount == stage.Count &&
                     status.VerifiedItemCount == stage.Count,
                    "Original DJ Library Inspect rejected publisher stage " +
                    stage.Name + ": " + status.Error);
                List<DJLibrary.DigitalItem> records =
                    DJLibrary.BridgeSnapshotReader.LoadItems(directory, status);
                Must(records.Count == stage.Count, "LoadItems count mismatch: " + stage.Name);
                var identities = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var track in records)
                {
                    Must(identities.Add(track.Path + "\n" +
                            track.Subsong.ToString(CultureInfo.InvariantCulture)),
                         "Duplicate identity: " + stage.Name);
                    Must(track.Artist == "Synthetic Artist" && track.Genre == "Trance" &&
                         track.Bpm == 128 && track.DurationSeconds == 240.5 &&
                         track.Codec == "FLAC" && track.Fingerprint.Length == 16,
                         "Core field projection mismatch: " + stage.Name);
                    using var json = JsonDocument.Parse(track.MetadataVectorsJson);
                    Must(json.RootElement.ValueKind == JsonValueKind.Array &&
                         json.RootElement.GetArrayLength() >= 3,
                         "Original reader lost lossless metadata vectors");
                }
                if (stage.Name == "g2-add")
                    oldFingerprint = records.Single(x => x.Title == "Alpha").Fingerprint;
                if (stage.Name == "g3-edit")
                    Must(records.Single(x => x.Title == "Alpha (updated)").Fingerprint != oldFingerprint,
                         "Changed track fingerprint did not propagate to original C# consumer");
                if (stage.Name == "g4-remove")
                    Must(records.Single().Title == "Alpha (updated)", "Removed item remained in C# reader");
                if (stage.Name == "g5-coalesced")
                    Must(records.Any(x => x.Title == "Burst final"), "Coalesced last value was lost");
                Console.WriteLine("NATIVE_PUBLISHER_TO_ORIGINAL_CSHARP_STAGE_" +
                                  stage.Generation + "=PASS count=" + records.Count);
            }
            Console.WriteLine("NATIVE_PUBLISHER_TO_ORIGINAL_DJ_LIBRARY=PASS");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("NATIVE_PUBLISHER_TO_ORIGINAL_DJ_LIBRARY=FAIL " + ex);
            return 1;
        }
    }
}
