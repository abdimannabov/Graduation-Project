import 'package:equatable/equatable.dart';
import '../entities/entities.dart';

class MyUser extends Equatable{
  final String userID;
  final String name;
  final String email;

  const MyUser({
    required this.userID,
    required this.name,
    required this.email,
  });
  
  static const empty = MyUser(
    userID: '', 
    name: '', 
    email: ''
  );

  MyUser copyWith({
    String? userID,
    String? name,
    String? email
  }) {
    return MyUser(
      userID: userID ?? this.userID, 
      name: name ?? this.name, 
      email: email ?? this.email
    );
  }

  MyUserEntity toEntity() {
    return MyUserEntity(
      userID: userID, 
      name: name, 
      email: email
    );
  }

  static MyUser fromEntity(MyUserEntity entity){
    return MyUser(
      userID: entity.userID, 
      name: entity.name, 
      email: entity.email
    );
  }

  @override
  List<Object?> get props => [userID, name, email];
}