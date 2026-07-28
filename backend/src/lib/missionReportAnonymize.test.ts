import { anonymizeVictimForPrompt } from "./missionReportAnonymize";

describe("anonymizeVictimForPrompt", () => {
  it("passes through only the free-text medical fields", () => {
    const result = anonymizeVictimForPrompt({
      chiefComplaint: "Θωρακικό άλγος",
      medicalHistory: "Υπέρταση",
      notes: "Μεταφέρθηκε σε νοσοκομείο",
    });

    expect(result).toEqual({
      chiefComplaint: "Θωρακικό άλγος",
      medicalHistory: "Υπέρταση",
      notes: "Μεταφέρθηκε σε νοσοκομείο",
    });
  });

  it("strips any extra fields present on the input object (e.g. accidental PII)", () => {
    const result = anonymizeVictimForPrompt({
      chiefComplaint: "Κάταγμα άκρου",
      medicalHistory: null,
      notes: null,
      // @ts-expect-error verifying extra fields are dropped even if present
      name: "Παπαδόπουλος Γεώργιος",
      telephone: "+302101234567",
    });

    expect(result).toEqual({
      chiefComplaint: "Κάταγμα άκρου",
      medicalHistory: null,
      notes: null,
    });
    expect(Object.keys(result)).toEqual(["chiefComplaint", "medicalHistory", "notes"]);
  });

  it("handles all-null fields", () => {
    const result = anonymizeVictimForPrompt({
      chiefComplaint: null,
      medicalHistory: null,
      notes: null,
    });
    expect(result).toEqual({ chiefComplaint: null, medicalHistory: null, notes: null });
  });
});
