// Copyright (c) 2020 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/file;
import ballerina/io;
import ballerina/log;
import ballerina/time;

type myCookie record {
    readonly string name;
    string value;
    readonly string domain;
    readonly string path;
    string expires;
    int maxAge;
    boolean httpOnly;
    boolean secure;
    string createdTime;
    string lastAccessedTime;
    boolean hostOnly;
};

# Represents a default persistent cookie handler, which stores persistent cookies in a CSV file.
#
# + fileName - Name of the CSV file to store persistent cookies
public isolated class CsvPersistentCookieHandler {
    *PersistentCookieHandler;

    private final string fileName;
    private table<myCookie> key(name, domain, path) cookiesTable = table [];

    public isolated function init(string fileName) {
        self.fileName = checkpanic validateFileExtension(fileName);
    }

    # Adds a persistent cookie to the cookie store.
    #
    # + cookie - Cookie to be added
    # + return - An error will be returned if there is any error occurred during the storing process of the cookie or else nil is returned
    public isolated function storeCookie(Cookie cookie) returns CookieHandlingError? {
        lock {
            if (fileExist(self.fileName) && self.cookiesTable.length() == 0) {
                var tblResult = readFile(self.fileName);
                if (tblResult is table<myCookie> key(name, domain, path)) {
                    self.cookiesTable = tblResult;
                } else {
                    return error CookieHandlingError("Error in reading the csv file", tblResult);
                }
            }
            var tableUpdateResult = addNewCookieToTable(self.cookiesTable, cookie);
            if (tableUpdateResult is table<myCookie> key(name, domain, path)) {
                self.cookiesTable = tableUpdateResult;
            } else {
                return error CookieHandlingError("Error in updating the records in csv file",
                cause = tableUpdateResult);
            }
            var result = writeToFile(self.cookiesTable, self.fileName);
            if (result is error) {
                return error CookieHandlingError("Error in writing the csv file", result);
            }
        }
        return;
    }

    # Gets all the persistent cookies.
    #
    # + return - Array of persistent cookies stored in the cookie store or else an error is returned if one occurred during the retrieval of the cookies
    public isolated function getAllCookies() returns Cookie[]|CookieHandlingError {
        Cookie[] cookies = [];
        if (fileExist(self.fileName)) {
            var tblResult = readFile(self.fileName);
            if (tblResult is table<myCookie> key(name, domain, path)) {
                foreach var rec in tblResult {
                    CookieOptions options = {};
                    options.domain = rec.domain;
                    options.path = rec.path;
                    if !(rec.expires == "-") {
                        options.expires = rec.expires;
                    }
                    options.maxAge = rec.maxAge;
                    options.httpOnly = rec.httpOnly;
                    options.secure = rec.secure;
                    time:Utc|error t1 = time:utcFromString(rec.createdTime);
                    if (t1 is time:Utc) {
                        options.createdTime = t1;
                    }
                    time:Utc|error t2 = time:utcFromString(rec.lastAccessedTime);
                    if (t2 is time:Utc) {
                        options.lastAccessedTime = t2;
                    }
                    options.hostOnly = rec.hostOnly;
                    Cookie cookie = new(rec.name, rec.value, options);
                    cookies.push(cookie);
                }
                return cookies;
            } else {
                return error CookieHandlingError("Error in reading the csv file", tblResult);
            }
        }
       return cookies;
    }

    # Removes a specific persistent cookie.
    #
    # + name - Name of the persistent cookie to be removed
    # + domain - Domain of the persistent cookie to be removed
    # + path - Path of the persistent cookie to be removed
    # + return - An error will be returned if there is any error occurred during the removal of the cookie or else nil is returned
    public isolated function removeCookie(string name, string domain, string path) returns CookieHandlingError? {
        if (fileExist(self.fileName)) {
            lock {
                if(self.cookiesTable.length() == 0) {
                    var tblResult = readFile(self.fileName);
                    if (tblResult is table<myCookie> key(name, domain, path)) {
                        self.cookiesTable = tblResult;
                    } else {
                        return error CookieHandlingError("Error in reading the csv file", tblResult);
                    }
                }
                _ = self.cookiesTable.remove([name, domain, path]);
                error? removeResults = file:remove(self.fileName);
                if (removeResults is error) {
                    return error CookieHandlingError("Error in removing the csv file", removeResults);
                }
                var writeResult = writeToFile(self.cookiesTable, self.fileName);
                if (writeResult is error) {
                    return error CookieHandlingError("Error in writing the csv file", writeResult);
                }
                return;
            }
        }
        return error CookieHandlingError("Error in removing cookie: No persistent cookie store file to remove");
    }

    # Removes all persistent cookies.
    #
    # + return - An error will be returned if there is any error occurred during the removal of all the cookies or else nil is returned
    public isolated function removeAllCookies() returns CookieHandlingError? {
        error? removeResults = file:remove(self.fileName);
        if (removeResults is error) {
            return error CookieHandlingError("Error in removing the csv file", removeResults);
        }
        return;
    }
}

isolated function validateFileExtension(string fileName) returns string|CookieHandlingError {
    if (fileName.toLowerAscii().endsWith(".csv")) {
        return fileName;
    }
    return error CookieHandlingError("Invalid file format");
}

isolated function readFile(string fileName) returns error|table<myCookie> key(name, domain, path) {
    io:ReadableCSVChannel rCsvChannel2 = check io:openReadableCsvFile(fileName);
    var tblResult = rCsvChannel2.toTable(myCookie, ["name", "domain", "path"]);
    closeReadableCSVChannel(rCsvChannel2);
    if (tblResult is table<record{| anydata...; |}>) {
        return <table<myCookie> key(name, domain, path)>tblResult;
    } else {
        return tblResult;
    }
}

isolated function closeReadableCSVChannel(io:ReadableCSVChannel csvChannel) {
    var result = csvChannel.close();
    if (result is error) {
        log:printError("Error occurred while closing the channel: ", 'error = result);
    }
}

// Updates the table with new cookie.
isolated function addNewCookieToTable(table<myCookie> key(name, domain, path) cookiesTable, Cookie cookieToAdd)
returns table<myCookie> key(name, domain, path)|error {
    table<myCookie> key(name, domain, path) tableToReturn = cookiesTable;
    var name = cookieToAdd.name;
    var value = cookieToAdd.value;
    var domain = cookieToAdd.domain;
    var path = cookieToAdd.path;
    var expires = cookieToAdd.expires;
    string createdTime = time:utcToString(cookieToAdd.createdTime);
    string lastAccessedTime = time:utcToString(cookieToAdd.lastAccessedTime);
    if (domain is string && path is string) {
        myCookie c1 = { name: name, value: value, domain: domain, path: path, expires: expires is string ?
        expires : "-", maxAge: cookieToAdd.maxAge, httpOnly: cookieToAdd.httpOnly, secure: cookieToAdd.secure,
        createdTime: createdTime, lastAccessedTime: lastAccessedTime, hostOnly: cookieToAdd.hostOnly };
        tableToReturn.add(c1);
        return tableToReturn;
    }
    return error CookieHandlingError("Invalid data types for cookie attributes");
}

// Writes the updated table to the file.
isolated function writeToFile(table<myCookie> key(name, domain, path) cookiesTable, string fileName) returns error? {
    io:WritableCSVChannel wCsvChannel2 = check io:openWritableCsvFile(fileName);
    foreach var entry in cookiesTable {
        string[] rec = [entry.name, entry.value, entry.domain, entry.path, entry.expires, entry.maxAge.toString(),
        entry.httpOnly.toString(), entry.secure.toString(), entry.createdTime, entry.lastAccessedTime,
        entry.hostOnly.toString()];
        var writeResult = writeDataToCSVChannel(wCsvChannel2, rec);
        if (writeResult is error) {
            return writeResult;
        }
    }
    closeWritableCSVChannel(wCsvChannel2);
    return;
}

isolated function writeDataToCSVChannel(io:WritableCSVChannel csvChannel, string[]... data) returns error? {
    foreach var rec in data {
        var returnedVal = csvChannel.write(rec);
        if (returnedVal is error) {
            return returnedVal;
        }
    }
    return;
}

isolated function closeWritableCSVChannel(io:WritableCSVChannel csvChannel) {
    var result = csvChannel.close();
    if (result is error) {
        log:printError("Error occurred while closing the channel: ", 'error = result);
    }
}

isolated function fileExist(string fileName) returns boolean {
    boolean|error fileTestResult = file:test(fileName, file:EXISTS);
    if (fileTestResult is boolean) {
        return fileTestResult;
    }
    return false;
}
