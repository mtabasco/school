// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

contract School {

    uint32 private constant STUDENTS_BLOCK = 4;

    uint256 private salaryPerBlock;

    // Sequential ids for simplicity and testing
    // Ids can be generated with keccak256(abi.encodePacked(param1, param2...)
    uint256 private counterCourseId;
    uint256 private counterStudentId;

    struct Student {
        string name;
        uint8 grade;
        uint256 courseId;
        uint256 studentId;
    }

    struct Course {
        string name;
        uint256 courseId;
        mapping (uint256 => bool) teachersInCourse;
    }

    mapping(uint256 => Course) private courses; // could be merged with courseTeachers
    mapping(uint256 => uint256[]) private courseTeachers; // courseId => teacherId[]

    mapping(string => Student) private students;

    // With this pattern, courseStudentToPosition keeps track of where is a student in a course's list of students
    // so we have O(1) fetching and updating the list of students in a course.
    // This is specially useful for moving students between courses
    mapping(uint256 => uint256) private courseStudentToPosition; // studentId => array index of courseStudents[studentId]
    mapping(uint256 => Student[]) private courseStudents;

    // Same pattern here for teachers but in this case, every student has it's own index for a teacher
    mapping(uint256 => mapping(uint256 => uint256)) private teacherStudentToPosition; // teacher - studentId - array index
    mapping(uint256 => Student[]) private teacherStudents;

    event StudentChange(uint256 indexed id, string name, uint256 courseId, uint8 grade);

    constructor(uint256 _salaryPerBlock) {
        salaryPerBlock = _salaryPerBlock;
    }

    /// @notice Avoid ETH deposits via regular transfers
    receive() payable external { }

    /// @notice Change salary per block of students.
    /// @param _salaryPerBlock The new salary amount per block (0 decimal precision)
    function changeSalaryPerBlock(uint256 _salaryPerBlock) external {
        require(_salaryPerBlock != 0, "Zero salary not allowed");
        salaryPerBlock = _salaryPerBlock;
    }

    /// @notice Register a course
    /// @dev _teacherIds can hold any list of Ids, they will be added to the course anyway
    /// @param _name Name of the course, UTF-8
    /// @param _teacherIds List of teachers assigned to the course
    function registerCourse(string memory _name, uint256[] memory _teacherIds) external { 
        bytes memory nameBytes = bytes(_name);
        require(nameBytes.length != 0, "Empty name not allowed");
        require(_teacherIds.length != 0, "Empty teachers list not allowed");

        Course storage courseData = courses[++counterCourseId];
        courseData.name = _name;
        courseData.courseId = counterCourseId;

        // Save directly the teachers list
        uint256 teachersLength = _teacherIds.length;
        for (uint i; i < teachersLength; ++i) {
            courseData.teachersInCourse[_teacherIds[i]] = true;
        }

        courseTeachers[courseData.courseId] = _teacherIds;
    }

    /// @notice Register a student in a course
    /// @dev _courseId should exists
    /// @param _name Name of the student
    /// @param _grade Grade of the student
    /// @param _courseId Id of the course
    function registerToCourse(string calldata _name, uint8 _grade, uint32 _courseId) external {
        bytes memory nameBytes = bytes(_name);
        require(nameBytes.length != 0, "Empty name not allowed");

        Student memory student = students[_name];
        require(student.studentId == 0, "Student already registered");

        // Create a new student
        Student memory newStudentData;
        newStudentData.name = _name;
        newStudentData.grade = _grade;
        newStudentData.courseId = _courseId;
        newStudentData.studentId = ++counterStudentId;

        students[_name] = newStudentData;

        // Save the student in the course and the index in the list of students in the course
        courseStudents[_courseId].push(newStudentData);        
        courseStudentToPosition[newStudentData.studentId] = courseStudents[_courseId].length - 1;

        // The student now is a student of every teacher in the course
        uint256[] memory teachers = courseTeachers[_courseId];
        for (uint i; i < teachers.length; ++i) {
            // Save the student in the teacher's list of students and the index in the list 
            // of students for him.
            teacherStudents[teachers[i]].push(newStudentData);
            teacherStudentToPosition[teachers[i]][newStudentData.studentId] = teacherStudents[teachers[i]].length - 1;
        }

        emit StudentChange(student.studentId, _name, _courseId, _grade); 
    }

    /// @notice Move a number of students, no matter from which course, to another course
    /// @param _names Names of the students
    /// @param _toCourseId Id of the target course
    function moveStudents(string[] calldata _names, uint256 _toCourseId) external {
        require(_names.length != 0, "Empty names list not allowed");

        Course storage toCourse = courses[_toCourseId];
        require(toCourse.courseId != 0, "Destination course not found");

        for (uint i; i < _names.length; ++i) {
            Student memory student = students[_names[i]];
            // if the student doesn't exist and the target course is equals the current one
            // just skip the move action and continue with the list of students
            if (student.studentId != 0 && student.courseId != _toCourseId) {
                
                uint256 courseStudentIndex = courseStudentToPosition[student.studentId];

                Student[] memory courseStudentList = courseStudents[student.courseId];

                uint256 courseStudentsLength = courseStudentList.length;

                // Remove the student from the list of students of the current course
                if(courseStudentsLength == 1) {
                    delete courseStudents[student.courseId];
                } else {
                    Student memory lastStudent = courseStudentList[courseStudentsLength - 1];
                    courseStudents[student.courseId][courseStudentIndex] = lastStudent;
                    courseStudents[student.courseId].pop();
                    courseStudentToPosition[lastStudent.studentId] = courseStudentIndex;
                }

                uint256 fromCourseId = student.courseId;

                // Add the student to the destination course and save the index position
                courseStudents[_toCourseId].push(student);
                courseStudentToPosition[student.studentId] = courseStudents[_toCourseId].length - 1;
                
                // Update the student in the students map
                student.courseId = _toCourseId;
                students[_names[i]] = student;

                uint256[] storage currentTeachers = courseTeachers[fromCourseId];
                
                for (uint j; j < currentTeachers.length; ++j) {
                    // key point to keep student with the same teacher 
                    // that overlaps in different courses:
                    // if the destination course has the same teacher, it means
                    // that the student is already a student of that teacher,
                    // so no need to update the student's list of the teacher
                    if(!toCourse.teachersInCourse[currentTeachers[j]]) {
                        uint256 studentIndex = teacherStudentToPosition[currentTeachers[j]][student.studentId];

                        Student[] memory studentList = teacherStudents[currentTeachers[j]];
                        if(studentList.length == 1) {
                            delete teacherStudents[currentTeachers[j]];
                        } else {
                            Student memory lastTeacherStudent = studentList[studentList.length - 1];
                            teacherStudents[currentTeachers[j]][studentIndex] = lastTeacherStudent;
                            teacherStudents[currentTeachers[j]].pop();
                            teacherStudentToPosition[currentTeachers[j]][lastTeacherStudent.studentId] = studentIndex;
                        }
                    }
                }

                Course storage fromCourse = courses[fromCourseId];
                uint256[] memory newTeachers = courseTeachers[_toCourseId];

                for (uint j; j < newTeachers.length; ++j) {
                    // key point to keep student with the same teacher 
                    // that overlaps in different courses:
                    // if the origin course has the same teacher,
                    // no need to update teacher's list
                    if(!fromCourse.teachersInCourse[newTeachers[j]]) {
                        teacherStudents[newTeachers[j]].push(student);
                        teacherStudentToPosition[newTeachers[j]][student.studentId] = teacherStudents[newTeachers[j]].length - 1;
                    }
                }

                emit StudentChange(student.studentId, student.name, student.courseId, student.grade);
            }
        }
    }

    /// @notice Get course average grade from all its students
    /// @dev result value has 1 decimal precision converted to uint: 3.4 -> 34, 5 -> 50
    /// @param _courseId Id of the course
    /// @return result the average grade of the course
    function getCourseAverageGrade(uint32 _courseId) public view returns (uint256 result) {
        Student[] memory studentList = courseStudents[_courseId];
        if (studentList.length == 0) {
            return result;
        }
        uint256 sum;
        for (uint i; i < studentList.length; ++i) {
            sum += studentList[i].grade;
        }

        // 1 decimal precision to uint
        result = (sum * 10) / studentList.length;
    }

    /// @notice Get the student count for one teacher
    /// @param _teacherId Id of the teacher
    /// @return count The number of students from all courses for a given teacher
    function getTeacherStudentCount(uint256 _teacherId) public view returns (uint256 count) {
        count = teacherStudents[_teacherId].length;
    }

    /// @notice Get teacher average grade from all its students, no matter from which course
    /// @dev result value has 1 decimal precision converted to uint: 3.4 -> 34, 5 -> 50
    /// @param _teacherId Id of the teacher
    /// @return result the average grade for all students of a given teacher
    function getTeacherAverageGrade(uint256 _teacherId) public view returns (uint256 result) {
        Student[] memory studentsList = teacherStudents[_teacherId];
        if (studentsList.length == 0) {
            return result;
        }
        uint256 sum;
        for (uint i; i < studentsList.length; ++i) {
            sum += studentsList[i].grade;
        }

        // 1 decimal precision to uint
        result = (sum * 10) / studentsList.length;
    }

    /// @notice Calculates the salary for a teacher, based on the number of students he teaches
    /// @dev Calculations are made converting 2 decimal precision into uint
    /// @param _teacherId Id of the teacher
    /// @return salary Computed salary
    function rewardTeacher(uint256 _teacherId) public view returns (uint256 salary) {
        Student[] memory studentsList = teacherStudents[_teacherId];
        if (studentsList.length == 0) {
            return salary;
        }
        // 2 decimal precision to uint
        uint256 blocks = (studentsList.length * 100) / STUDENTS_BLOCK;
        salary = (salaryPerBlock / 100) * blocks;
    }

}