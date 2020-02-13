// PURPOSE: Creates "snapshots" of records of any object type and criteria specified in
// a custom object record Database_Snapshot_Rule__c. Fields are mapped from source to target
// object via child records of type Database_Snapshot_Field_Mapping__c.
// -----------------------------------------
// CODE EXPLANATION: Acts as an alternative to the native 'Reporting Snapshot' feature in Salesforce so
// more advanced "snapshots" can be taken and reported upon, and snapshots are easier to configure.
// Snapshots take a "picture" of a specific database object and its records in the present time,
// including all records that meet a selection criteria. Desired fields are taken from the source
// records and translated into fields on records of a different object type for reporting on 
// "what was the state of X records at Y time?"
global class DatabaseSnapshot implements Schedulable {
    
    private Map<String,String> fieldMap;
    private String entryCriteria;
    private String sourceObjName;
    private String targetObjName;
    private String snapshotRuleId;
    private Database_Snapshot_Rule__c definition;
    private boolean dryRun = false;

    // Constructor 1. Requires the following parameters:
    // - ID of a Database_Snapshot_Rule__c record specifying snapshot behavior
    global DatabaseSnapshot(String ruleId) 
    {
        this.snapshotRuleId  = ruleId;
        this.definition      = retrieveRule();
        this.fieldMap        = retrieveFieldMappings();
        this.sourceObjName   = definition.Source_Object__c;
        this.targetObjName   = definition.Target_Object__c;
        this.entryCriteria   = definition.Entry_Criteria__c;
    }

    // Constructor 2. Requires the following parameters:
    // - ID of a Database_Snapshot_Rule__c record specifying snapshot behavior
    // - Boolean to indicate if a snapshot should be committed to the database or not
    global DatabaseSnapshot(String ruleId, boolean testOnly) 
    {
        this.snapshotRuleId  = ruleId;
        this.dryRun          = testOnly;
        this.definition      = retrieveRule();
        this.fieldMap        = retrieveFieldMappings();
        this.sourceObjName   = definition.Source_Object__c;
        this.targetObjName   = definition.Target_Object__c;
        this.entryCriteria   = definition.Entry_Criteria__c;
    }
    
    // Retrieve Database Snapshot Rule record based on its ID
    private Database_Snapshot_Rule__c retrieveRule()
    { 
        Database_Snapshot_Rule__c definition = [
            SELECT ID,Entry_Criteria__c,Rule_Frequency__c,Source_Object__c,Target_Object__c
            FROM Database_Snapshot_Rule__c WHERE ID =: snapshotRuleId
        ];
        return definition;
    }

    // Retrieve child record field mappings under the parent Database Snapshot Rule
    // Put SOURCE -> TARGET field definitions into Map
    private Map<String,String> retrieveFieldMappings()
    {
        Map<String,String> fieldMapping = new Map<String,String>();
        Database_Snapshot_Field_Mapping__c[] mappings = [
            SELECT Source_Field__c,Target_Field__c
            FROM Database_Snapshot_Field_Mapping__c
            WHERE Database_Snapshot_Rule__c =: definition.Id
        ];
        for (Database_Snapshot_Field_Mapping__c fieldMap : mappings)
        {
            fieldMapping.put(fieldMap.Source_Field__c,fieldMap.Target_Field__c);
        }
        return fieldMapping;
    }

    // Build query string for dynamic query of source sObject records
    public String buildQuery()
    {
        String[] sourceFields = new List<String>();
        sourceFields.addall(fieldMap.keySet());
        String fields = String.valueOf(sourceFields).replace('(','').replace(')',''); // Add regex later
        String sourceQuery = 'SELECT '+fields+' FROM '+sourceObjName+' WHERE '+entryCriteria;
        system.debug(sourceQuery);
        return sourceQuery;
    }

    // Creates snapshot records for the particular snapshot record defined
    // Essentially translates records from SOURCE type to TARGET type for reporting
    public void takeSnapshot()
    {
        // Dynamically query records in Source Object with fields provided by MDT field mappings
        sObject[] sourceRecords = Database.query(buildQuery());
        system.debug(sourceRecords);
        // ***** need to account if there are 0 records, what do we do then?
        // ***** maybe create a Database Snapshot Log object of some kind which summarizes
        // ***** the information

        // Get object type from targetObjName as defined in Rule record
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(targetObjName);
        if (targetType == null) 
        {
            // throw an exception
        }

        // Create records of dynamic target object type
        sObject[] targetRecords = new List<sObject>();
        for (sObject sourceRecord : sourceRecords) {
            // Instance object of dynamic type
            sObject newRecord = targetType.newSObject();
            // Loop thru fields and add values set by field mapping object
            for (String sourceField : fieldMap.keySet()) {
                // Later: add support for compound fields / relationship fields:
                   // https://salesforce.stackexchange.com/questions/118540/retrieving-dynamic-soql-results-runtime-error-invalid-field-owner-name-for
                newRecord.put(fieldMap.get(sourceField),sourceRecord.get(sourceField));
            }
            targetRecords.add(newRecord);
            system.debug(targetRecords.size());
        }

        // Insert new records of dynamic type into the database
        Savepoint sp = Database.setSavepoint();
        if (!targetRecords.isEmpty())
        {
            database.insert(targetRecords,true);
        } 
        if (!targetRecords.isEmpty() && dryRun)
        {
            Database.rollback(sp); // Dry run; rollback to the previous state
        } 
    }

    // Schedulabled apex job definition -- Take a snapshot on specified scheduled context
    global void execute(SchedulableContext sc)
    {
        try {
            takeSnapshot();
        } 
        catch (Exception e) {
            // Do things here e.g. warn user that Rule or Field Mapping invalid
        }
    }

    // Validates values put into Source_Field__c and Target_Field__c fields on the
    // Database_Snapshot_Field_Mapping__c record in a trigger (update or create) op
    public boolean areFieldsValid(Database_Snapshot_Field_Mapping__c mapping)
    {
        // Do a Schema.getDescribe() call to validate that fields exist
        return false;
        // If false, throw error in trigger calling this function and prevent save
    }

    // Validates Entry_Criteria__c field on the Database_Snapshot_Rule__c definition
    // in a trigger (update or create) op
    public boolean isQueryValid()
    {
        try {
            String criteriaTest = 'SELECT ID FROM '+sourceObjName+' WHERE '+entryCriteria;
            sObject[] sourceRecords = Database.query(criteriaTest);
        } 
        catch (Exception e)
        {
            // throw new error
        }
        return true;
    }

    // Validates Source_Object__c and Target_Object__c fields on Database_Snapshot_Rule__c definition
    // in a trigger (update or create) op
    public boolean areObjectsValid()
    {
        // Do a Schema.getDescribe() call to validate that Source_Object__c and Target_Object__c
        // values correspond to valid sObject types in the database
        return false;
        // If false, throw error in the trigger calling this function and prevent save
    }



}