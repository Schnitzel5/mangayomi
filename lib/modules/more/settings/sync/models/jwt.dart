class JWToken {
  String? uuid;
  String? email;
  String? mangaSourcesListUrl;
  String? animeSourcesListUrl;
  int? iat;
  int? exp;

  JWToken({this.uuid, this.email, this.iat, this.exp});

  JWToken.fromJson(Map<String, dynamic> json) {
    uuid = json['uuid'];
    email = json['email'];
    mangaSourcesListUrl = json['mangaSourcesListUrl'];
    animeSourcesListUrl = json['animeSourcesListUrl'];
    iat = (json['iat'] as int) * 1000;
    exp = (json['exp'] as int) * 1000;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['uuid'] = uuid;
    data['email'] = email;
    data['mangaSourcesListUrl'] = email;
    data['animeSourcesListUrl'] = email;
    data['iat'] = iat;
    data['exp'] = exp;
    return data;
  }
}
