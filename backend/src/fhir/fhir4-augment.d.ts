// Augment fhir4.Resource to expose resourceType, which is defined on
// concrete subtypes but not on the base Resource interface in @types/fhir.
// This allows test code to use r.resourceType for type-narrowing.
declare namespace fhir4 {
  interface Resource {
    resourceType: string;
  }
}
